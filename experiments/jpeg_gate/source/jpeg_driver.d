module jpeg_driver;

import std.file : read, write;
import std.stdio : writeln;
import std.conv : to;
import jpeg_research;

void main(string[] args)
{
    if (args.length == 5 && args[1] == "inspectmeta")
    {
        auto file = cast(ubyte[])read(args[2]);
        auto exif = args[3] == "-" ? null : cast(ubyte[])read(args[3]);
        auto icc = args[4] == "-" ? null : cast(ubyte[])read(args[4]);
        MetadataSegment[255] parts;
        if (icc.length)
        {
            parts[0] = MetadataSegment(123, 456);
            auto tooSmall = inspectJpegMetadata(file[], parts[0 .. 0]);
            assert(tooSmall.status == Status.destinationTooSmall);
            assert(parts[0].offset == 123 && parts[0].length == 456);
        }
        auto info = inspectJpegMetadata(file[], parts[]);
        assert(info.ok);
        assert(info.exifLength == exif.length);
        if (exif.length)
            assert(file[info.exifOffset .. info.exifOffset + info.exifLength] == exif);
        assert(info.iccBytes == icc.length);
        auto rebuilt = new ubyte[info.iccBytes];
        size_t position;
        foreach (size_t i; 0 .. info.iccSegments)
        {
            const part = parts[i];
            rebuilt[position .. position + part.length] =
                file[part.offset .. part.offset + part.length];
            position += part.length;
        }
        assert(rebuilt == icc);
        writeln("metadata inspect EXIF=", info.exifLength,
            " ICC=", info.iccBytes, " segments=", info.iccSegments);
        return;
    }
    if (args.length == 3 && args[1] == "inspectnegative")
    {
        auto file = cast(ubyte[])read(args[2]);
        MetadataSegment[255] parts;
        assert(!inspectJpegMetadata(file[], parts[]).ok);
        return;
    }
    if (args.length == 6 && args[1] == "metadata")
    {
        auto raw = cast(ubyte[])read(args[2]);
        auto exif = cast(ubyte[])read(args[3]);
        auto icc = cast(ubyte[])read(args[4]);
        assert(raw.length == 19 * 11 * 3);
        auto metadata = EncodeMetadata(exif[], icc[]);
        const iccSegments = (icc.length + 65518) / 65519;
        auto outputBytes = new ubyte[1024 + 6 * 3 * 512 + 4 +
            exif.length + icc.length + iccSegments * 18];
        outputBytes[] = 0xa5;
        assert(encodeJpeg(Info(19, 11, 3), raw[], 19 * 3,
            outputBytes[], EncodeOptions(95), metadata).status ==
            Status.unsupported);
        assert(encodeJpeg(Info(19, 11, 3), raw[], 19 * 3,
            outputBytes[], EncodeOptions(95, Sampling.s444, 0,
                MetadataPolicy.copy), EncodeMetadata(exif[0 .. 5], icc[])).status ==
            Status.invalid);
        assert(encodeJpeg(Info(19, 11, 3), raw[], 19 * 3,
            outputBytes[], EncodeOptions(95, Sampling.s444, 0,
                MetadataPolicy.copy), EncodeMetadata(exif[], icc[0 .. 20])).status ==
            Status.invalid);
        foreach (value; outputBytes) assert(value == 0xa5);
        auto copied = encodeJpeg(Info(19, 11, 3), raw[], 19 * 3,
            outputBytes[], EncodeOptions(95, Sampling.s444, 0,
                MetadataPolicy.copy), metadata);
        assert(copied.ok && copied.metadataDisposition ==
            MetadataDisposition.copied);
        write(args[5], outputBytes[0 .. copied.written]);
        auto dropped = encodeJpeg(Info(19, 11, 3), raw[], 19 * 3,
            outputBytes[], EncodeOptions(95, Sampling.s444, 0,
                MetadataPolicy.discard), metadata);
        assert(dropped.ok && dropped.metadataDisposition ==
            MetadataDisposition.discarded);
        write(args[5] ~ ".drop.jpg", outputBytes[0 .. dropped.written]);
        return;
    }
    if ((args.length >= 4 && args.length <= 7) && args[1] == "encode")
    {
        const ubyte quality = args.length >= 5 ? to!ubyte(args[4]) : 75;
        const sampling = args.length >= 6 && args[5] == "422" ? Sampling.s422 :
            args.length >= 6 && args[5] == "420" ? Sampling.s420 : Sampling.s444;
        const ushort restart = args.length == 7 ? to!ushort(args[6]) : 0;
        assert(args.length < 6 || args[5] == "444" ||
            args[5] == "422" || args[5] == "420");
        auto raw = cast(ubyte[])read(args[2]);
        const channels = cast(ubyte)(raw.length == 19 * 11 ? 1 : 3);
        assert(raw.length == 19 * 11 * channels);
        assert(channels == 3 || sampling == Sampling.s444);
        const size_t h = sampling == Sampling.s444 ? 1 : 2;
        const size_t v = sampling == Sampling.s420 ? 2 : 1;
        const capacity = 1024 + ((19 + 8 * h - 1) / (8 * h)) *
            ((11 + 8 * v - 1) / (8 * v)) *
            (channels == 1 ? 1 : h * v + 2) * 512;
        auto outputBytes = new ubyte[capacity];
        outputBytes[] = 0xa5;
        assert(encodeJpeg(Info(19, 11, channels), raw[],
            19 * channels, outputBytes[], EncodeOptions(0)).status == Status.invalid);
        assert(encodeJpeg(Info(19, 11, channels), raw[],
            19 * channels, outputBytes[], EncodeOptions(101)).status == Status.invalid);
        foreach (value; outputBytes) assert(value == 0xa5);
        assert(encodeJpeg(Info(19, 11, channels), raw[],
            19 * channels, outputBytes[][0 .. $ - 1],
            EncodeOptions(quality, sampling, restart)).status ==
            Status.destinationTooSmall);
        foreach (value; outputBytes) assert(value == 0xa5);
        auto result = encodeJpeg(Info(19, 11, channels), raw[],
            19 * channels, outputBytes[], EncodeOptions(quality, sampling, restart));
        assert(result.ok);
        auto reopened = new ubyte[raw.length];
        auto decoded = decodeJpeg(outputBytes[0 .. result.written],
            reopened[], 19 * channels);
        assert(decoded.ok && decoded.written == raw.length);
        write(args[3], outputBytes[0 .. result.written]);
        writeln(args[3], " encoded_bytes=", result.written);
        return;
    }
    if (args.length == 3 && args[1] == "negative")
    {
        auto file = cast(ubyte[])read(args[2]);
        ubyte[19 * 11 * 3] output;
        assert(!decodeJpeg(file[], output[], 19 * 3).ok);
        return;
    }
    if (args.length == 3 && args[1] == "fuzz")
    {
        auto file = cast(ubyte[])read(args[2]);
        ubyte[19 * 11 * 3 + 2] output;
        foreach (size_t p; 0 .. file.length)
        {
            const original = file[p];
            file[p] ^= 0xff;
            output[] = 0xa5;
            auto result = decodeJpeg(file[], output[1 .. $ - 1], 19 * 3);
            assert(output[0] == 0xa5 && output[$ - 1] == 0xa5);
            file[p] = original;
        }
        foreach (size_t n; 0 .. file.length)
        {
            output[] = 0xa5;
            auto result = decodeJpeg(file[0 .. n], output[1 .. $ - 1], 19 * 3);
            assert(output[0] == 0xa5 && output[$ - 1] == 0xa5);
        }
        writeln("mutation/truncation cases=", 2 * file.length);
        return;
    }
    assert(args.length == 3);
    auto file = cast(ubyte[])read(args[1]);
    auto expected = cast(ubyte[])read(args[2]);
    ubyte[19 * 11 * 3] output;
    auto result = decodeJpeg(file[], output[], 19 * (expected.length == 19 * 11 ? 1 : 3));
    assert(result.ok, "baseline JPEG decode failed");
    assert(result.written == expected.length);
    uint maxError;
    ulong sum;
    foreach (size_t i, value; expected)
    {
        const difference = output[i] > value ? output[i] - value : value - output[i];
        if (difference > maxError) maxError = difference;
        sum += difference;
    }
    writeln(args[1], " max_error=", maxError, " mean_error=",
        cast(double)sum / expected.length);
    // The subsampled paths must now interpolate across MCU boundaries.
    // Small differences from Pillow's IDCT/colour rounding remain possible.
    assert(maxError <= 3);
}
