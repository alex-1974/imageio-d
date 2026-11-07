/// Consumer-shaped technical read/modify/write probe; no imagery semantics.
module jpeg_native_pipeline_probe;

import jpeg_research;
import std.file : read, write;

void main(string[] args)
{
    assert(args.length == 5);
    auto source = cast(ubyte[])read(args[1]);
    auto expectedExif = cast(ubyte[])read(args[2]);
    auto expectedIcc = cast(ubyte[])read(args[3]);
    auto frame = inspectJpegFrame(source[]);
    assert(frame.ok && frame.signal == ComponentSignal.jfifYCbCr &&
        frame.info.components == 3);
    const h = frame.horizontal[0], v = frame.vertical[0];
    assert(h == 1 && v == 1); // Current metadata fixture is 4:4:4.
    ubyte[][3] samples;
    MutablePlane[3] destination;
    ConstPlane[3] input;
    foreach (size_t c; 0 .. 3)
    {
        samples[c] = new ubyte[frame.info.width * frame.info.height];
        destination[c] = MutablePlane(samples[c], frame.info.width);
        input[c] = ConstPlane(samples[c], frame.info.width);
    }
    MetadataSegment[255] segments;
    auto decoded = decodeJpegPlanesAudited(source[], destination[],
        segments[], ReadMetadataPolicy.report);
    assert(decoded.ok && decoded.metadataDisposition ==
        ReadMetadataDisposition.reported);
    assert(decoded.metadata.opaqueSegments == 0);
    assert(decoded.metadata.exifLength == expectedExif.length &&
        decoded.metadata.iccBytes == expectedIcc.length);
    auto exif = source[decoded.metadata.exifOffset ..
        decoded.metadata.exifOffset + decoded.metadata.exifLength];
    assert(exif == expectedExif);
    auto icc = new ubyte[decoded.metadata.iccBytes];
    size_t offset;
    foreach (size_t i; 0 .. decoded.metadata.iccSegments)
    {
        const part = segments[i];
        icc[offset .. offset + part.length] =
            source[part.offset .. part.offset + part.length];
        offset += part.length;
    }
    assert(offset == icc.length && icc == expectedIcc);
    // Technical one-sample edit only. This deliberately does not claim an
    // imagery-d processing operation or a colour-managed editor workflow.
    samples[0][0] = cast(ubyte)(samples[0][0] == 255 ?
        254 : samples[0][0] + 1);
    const metadata = EncodeMetadata(exif[], icc[]);
    auto output = new ubyte[1024 + 6 * 3 * 512 + 4 + exif.length +
        icc.length + ((icc.length + 65518) / 65519) * 18];
    auto copied = encodeJfifPlanes(frame.info, input[], output[],
        EncodeOptions(95, Sampling.s444, 0, MetadataPolicy.copy), metadata);
    assert(copied.ok && copied.metadataDisposition ==
        MetadataDisposition.copied);
    write(args[4], output[0 .. copied.written]);
    MetadataSegment[255] outputParts;
    auto preserved = inspectJpegMetadata(output[0 .. copied.written],
        outputParts[]);
    assert(preserved.ok && preserved.exifLength == exif.length &&
        preserved.iccBytes == icc.length);
    auto discarded = encodeJfifPlanes(frame.info, input[], output[],
        EncodeOptions(95, Sampling.s444, 0, MetadataPolicy.discard), metadata);
    assert(discarded.ok && discarded.metadataDisposition ==
        MetadataDisposition.discarded);
    write(args[4] ~ ".drop.jpg", output[0 .. discarded.written]);
    auto absent = inspectJpegMetadata(output[0 .. discarded.written],
        outputParts[]);
    assert(absent.ok && absent.exifLength == 0 && absent.iccBytes == 0);
}
