module oracle_compare;

import std.file : read;
import std.stdio : writefln;
import std.conv : to;
import ifd_result : parse, Status;

void main(string[] args)
{
    auto fixture = args.length > 1 ? args[1] : "experiments/tiff_core/.build/oracle-gray16.tif";
    auto expectedWidth = args.length > 2 ? to!uint(args[2]) : 16;
    auto expectedHeight = args.length > 3 ? to!uint(args[3]) : 8;
    auto expectedSamples = args.length > 4 ? to!uint(args[4]) : 1;
    auto bytes = cast(const(ubyte)[]) read(fixture);
    auto result = parse(bytes);
    assert(result.status == Status.ok);
    assert(result.value.width == expectedWidth);
    assert(result.value.height == expectedHeight);
    assert(result.value.samplesPerPixel == expectedSamples);
    assert(result.value.bitsPerSampleCount != 0);
    if (expectedSamples > 1)
        assert(result.value.bitsPerSampleCount == expectedSamples && result.value.bitsPerSampleOffset != 0);
    writefln("Pure-D oracle: width=%s height=%s samples=%s bits=%s compression=%s",
        result.value.width, result.value.height, result.value.samplesPerPixel,
        result.value.bitsPerSample, result.value.compression);
    writefln("strip-count=%s tile-count=%s planar=%s strip-offset=%s strip-bytes=%s",
        result.value.stripOffsets.count, result.value.tileOffsets.count,
        result.value.planarConfiguration, result.value.stripOffsets.valueOffset,
        result.value.stripByteCounts.valueOffset);
}
