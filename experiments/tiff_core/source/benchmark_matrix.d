module benchmark_matrix;

import std.datetime.stopwatch : StopWatch;
import std.random : Random, unpredictableSeed, uniform;
import std.stdio : writefln;
import payload_decode : Layout, decodeInterleaved, decodePlanarBlocked, decodePlanar3x16;

pragma(inline, false)
ulong consume(scope const(ubyte)[] data) @safe
{
    ulong result;
    foreach (value; data)
        result = result * 131 + value;
    return result;
}

void runCase(uint width, uint height, uint bands, uint sampleBytes, bool planar)
{
    enum iterations = 20;
    auto byteCount = cast(size_t) width * height * bands * sampleBytes;
    auto source = new ubyte[byteCount];
    auto destination = new ubyte[byteCount];
    auto random = Random(unpredictableSeed);
    foreach (ref value; source)
        value = uniform!ubyte(random);

    StopWatch watch;
    watch.start();
    size_t copied;
    ulong checksum;
    foreach (i; 0 .. iterations)
    {
        auto result = planar
            ? ((bands == 3 && sampleBytes == 2)
                ? decodePlanar3x16(source[], width, height, destination[],
                    Layout(width * bands * sampleBytes, bands * sampleBytes, sampleBytes))
                : decodePlanarBlocked(source[], width, height, bands, sampleBytes, 32, 32,
                    destination[], Layout(width * bands * sampleBytes, bands * sampleBytes, sampleBytes)))
            : decodeInterleaved(source[], width, height, bands, sampleBytes,
                destination[], Layout(width * bands * sampleBytes, bands * sampleBytes, sampleBytes));
        assert(result.ok);
        copied += result.written;
        checksum += consume(destination[]);
    }
    auto elapsed = watch.peek.total!"msecs";
    writefln("mode=%s size=%sx%s bands=%s sample_bytes=%s iterations=%s bytes=%s checksum=%s elapsed_ms=%s",
        planar ? "planar" : "interleaved", width, height, bands, sampleBytes,
        iterations, copied, checksum, elapsed);
}

void main()
{
    runCase(256, 256, 1, 1, false);
    runCase(256, 256, 3, 2, false);
    runCase(256, 256, 4, 4, false);
    runCase(256, 256, 3, 2, true);
    runCase(1024, 1024, 1, 1, false);
    runCase(1024, 1024, 3, 2, true);
}
