module benchmark;

import std.datetime.stopwatch : StopWatch;
import std.random : Random, unpredictableSeed, uniform;
import std.stdio : writefln;
import payload_decode : Layout, decodeInterleaved;

pragma(inline, false)
ulong consume(scope const(ubyte)[] data) @safe
{
    ulong result;
    foreach (value; data)
        result = result * 131 + value;
    return result;
}

@safe
void main()
{
    enum width = 256;
    enum height = 256;
    enum bands = 2;
    enum sampleBytes = 2;
    enum iterations = 1000;
    ubyte[width * height * bands * sampleBytes] source;
    ubyte[width * height * bands * sampleBytes] destination;
    auto random = Random(unpredictableSeed);
    foreach (ref value; source)
        value = uniform!ubyte(random);

    StopWatch watch;
    watch.start();
    size_t copied;
    ulong checksum;
    foreach (i; 0 .. iterations)
    {
        auto result = decodeInterleaved(
            source[], width, height, bands, sampleBytes,
            destination[], Layout(width * bands * sampleBytes, bands * sampleBytes, sampleBytes)
        );
        assert(result.ok);
        copied += result.written;
        checksum += consume(destination[]);
    }
    auto elapsed = watch.peek.total!"msecs";
    writefln("iterations=%s bytes=%s checksum=%s elapsed_ms=%s", iterations, copied, checksum, elapsed);
}
