/// Explicit EXIF/ICC read-policy probe. No metadata interpretation.
module jpeg_metadata_read_probe;

import jpeg_research;
import std.file : read;

void main(string[] args)
{
    assert(args.length == 4 || args.length == 3 && args[1] == "bad");
    const bad = args[1] == "bad";
    auto file = cast(ubyte[])read(args[bad ? 2 : 1]);
    auto frame = inspectJpegFrame(file[]);
    assert(frame.ok && frame.info.width == 19 && frame.info.height == 11 &&
        frame.info.components == 3);
    ubyte[19 * 11 + 32][3] storage;
    MutablePlane[3] planes;
    foreach (size_t c; 0 .. 3)
    {
        storage[c][] = 0xa5;
        planes[c] = MutablePlane(storage[c][16 .. $ - 16], 19);
    }
    MetadataSegment[255] iccSegments;
    if (bad)
    {
        auto failed = decodeJpegPlanesAudited(file[], planes[],
            iccSegments[], ReadMetadataPolicy.report);
        assert(failed.pixels.status == Status.invalid);
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
        return;
    }
    auto exif = args[2] == "-" ? null : cast(ubyte[])read(args[2]);
    auto icc = args[3] == "-" ? null : cast(ubyte[])read(args[3]);
    const hasMetadata = exif.length != 0 || icc.length != 0;
    auto rejected = decodeJpegPlanesAudited(file[], planes[],
        iccSegments[], ReadMetadataPolicy.reject);
    assert(rejected.pixels.status == (hasMetadata ? Status.unsupported : Status.ok));
    if (hasMetadata)
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
    foreach (ref samples; storage) samples[] = 0xa5;
    auto invalidPolicy = decodeJpegPlanesAudited(file[], planes[],
        iccSegments[], cast(ReadMetadataPolicy)3);
    assert(invalidPolicy.pixels.status == Status.invalid);
    auto limited = decodeJpegPlanesAudited(file[], planes[],
        iccSegments[], ReadMetadataPolicy.report,
        Limits(file.length - 1, 64_000_000));
    assert(limited.pixels.status == Status.limit);
    foreach (ref samples; storage)
        foreach (value; samples) assert(value == 0xa5);
    if (icc.length != 0)
    {
        iccSegments[0] = MetadataSegment(123, 456);
        auto shortReport = decodeJpegPlanesAudited(file[], planes[],
            iccSegments[0 .. 0], ReadMetadataPolicy.report);
        assert(shortReport.pixels.status == Status.destinationTooSmall);
        assert(iccSegments[0].offset == 123 && iccSegments[0].length == 456);
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
    }
    auto reported = decodeJpegPlanesAudited(file[], planes[],
        iccSegments[], ReadMetadataPolicy.report);
    assert(reported.ok && reported.frame.signal == ComponentSignal.jfifYCbCr);
    assert(reported.metadataDisposition == (hasMetadata ?
        ReadMetadataDisposition.reported : ReadMetadataDisposition.none));
    assert(reported.metadata.exifLength == exif.length);
    if (exif.length)
        assert(file[reported.metadata.exifOffset ..
            reported.metadata.exifOffset + exif.length] == exif[]);
    assert(reported.metadata.iccBytes == icc.length);
    auto rebuilt = new ubyte[icc.length];
    size_t position;
    foreach (size_t i; 0 .. reported.metadata.iccSegments)
    {
        const part = iccSegments[i];
        assert(position + part.length <= rebuilt.length);
        rebuilt[position .. position + part.length] =
            file[part.offset .. part.offset + part.length];
        position += part.length;
    }
    assert(position == icc.length && rebuilt == icc);
    foreach (ref samples; storage)
    {
        foreach (value; samples[0 .. 16]) assert(value == 0xa5);
        foreach (value; samples[$ - 16 .. $]) assert(value == 0xa5);
        samples[] = 0xa5;
    }
    auto discarded = decodeJpegPlanesAudited(file[], planes[],
        iccSegments[0 .. 0], ReadMetadataPolicy.discard);
    assert(discarded.ok && discarded.metadataDisposition == (hasMetadata ?
        ReadMetadataDisposition.discarded : ReadMetadataDisposition.none));
    foreach (ref samples; storage)
    {
        foreach (value; samples[0 .. 16]) assert(value == 0xa5);
        foreach (value; samples[$ - 16 .. $]) assert(value == 0xa5);
    }
    if (!hasMetadata)
    {
        immutable ubyte[] extra = [0xff, 0xe3, 0, 6, 1, 2, 3, 4,
            0xff, 0xfe, 0, 4, 5, 6];
        auto opaque = file[0 .. 20].dup ~ extra ~ file[20 .. $].dup;
        auto inventory = inspectJpegMetadata(opaque[], iccSegments[]);
        assert(inventory.ok && inventory.opaqueSegments == 2 &&
            inventory.opaqueBytes == 6);
        foreach (ref samples; storage) samples[] = 0xa5;
        auto refused = decodeJpegPlanesAudited(opaque[], planes[],
            iccSegments[], ReadMetadataPolicy.reject);
        assert(refused.pixels.status == Status.unsupported);
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
        auto disclosed = decodeJpegPlanesAudited(opaque[], planes[],
            iccSegments[], ReadMetadataPolicy.report);
        assert(disclosed.ok && disclosed.metadataDisposition ==
            ReadMetadataDisposition.reported &&
            disclosed.metadata.opaqueSegments == 2);
        foreach (ref samples; storage) samples[] = 0xa5;
        auto thrownAway = decodeJpegPlanesAudited(opaque[], planes[],
            iccSegments[0 .. 0], ReadMetadataPolicy.discard);
        assert(thrownAway.ok && thrownAway.metadataDisposition ==
            ReadMetadataDisposition.discarded);
        assert(file[2] == 0xff && file[3] == 0xe0 &&
            file[4] == 0 && file[5] == 16);
        auto changedDensity = file.dup;
        changedDensity[15] = 2; // JFIF X density: writer would reset to 1.
        auto densityInfo = inspectJpegMetadata(changedDensity[], iccSegments[]);
        assert(densityInfo.ok && densityInfo.containerLossSegments == 1 &&
            densityInfo.containerLossBytes == 14);
        foreach (ref samples; storage) samples[] = 0xa5;
        auto densityRefused = decodeJpegPlanesAudited(changedDensity[],
            planes[], iccSegments[], ReadMetadataPolicy.reject);
        assert(densityRefused.pixels.status == Status.unsupported);
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
        auto densityDisclosed = decodeJpegPlanesAudited(changedDensity[],
            planes[], iccSegments[], ReadMetadataPolicy.report);
        assert(densityDisclosed.ok && densityDisclosed.metadataDisposition ==
            ReadMetadataDisposition.reported);
        immutable ubyte[] adobe = [0xff, 0xee, 0, 14,
            'A', 'd', 'o', 'b', 'e', 0, 100, 0, 0, 0, 0, 0];
        auto adobeFile = file[0 .. 20].dup ~ adobe ~ file[20 .. $].dup;
        auto adobeInfo = inspectJpegMetadata(adobeFile[], iccSegments[]);
        assert(adobeInfo.ok && adobeInfo.containerLossSegments == 1 &&
            adobeInfo.containerLossBytes == 12);
        foreach (ref samples; storage) samples[] = 0xa5;
        auto adobeRefused = decodeJpegPlanesAudited(adobeFile[], planes[],
            iccSegments[], ReadMetadataPolicy.reject);
        assert(adobeRefused.pixels.status == Status.unsupported);
        foreach (ref samples; storage)
            foreach (value; samples) assert(value == 0xa5);
        auto adobeDisclosed = decodeJpegPlanesAudited(adobeFile[], planes[],
            iccSegments[], ReadMetadataPolicy.report);
        assert(adobeDisclosed.ok && adobeDisclosed.frame.signal ==
            ComponentSignal.adobeRGB && adobeDisclosed.metadataDisposition ==
            ReadMetadataDisposition.reported);
    }
}
