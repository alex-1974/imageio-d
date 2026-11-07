module local_range_probe;

import std.file : read;
import std.stdio : writefln;

struct RangeResult
{
    bool ok;
    size_t bytes;
}

struct RangeMetrics
{
    size_t requests;
    size_t encodedBytes;
    size_t decodedBytes;
    @property double amplification() const @safe pure nothrow @nogc
    { return encodedBytes == 0 ? 0 : cast(double)decodedBytes / encodedBytes; }
}

struct LocalRangeSource
{
    const(ubyte)[] bytes;
    size_t requests;
    size_t requestedBytes;

    RangeResult readRange(size_t offset, size_t length, ubyte[] destination)
        @safe nothrow
    {
        if (offset > bytes.length || length > bytes.length - offset
            || destination.length < length)
            return RangeResult(false, 0);
        destination[0 .. length] = bytes[offset .. offset + length];
        ++requests;
        requestedBytes += length;
        return RangeResult(true, length);
    }
}

version (LocalRangeProbe)
void main(string[] args)
{
    assert(args.length > 1, "provide a fixture");
    auto input = cast(const(ubyte)[]) read(args[1]);
    LocalRangeSource source = LocalRangeSource(input);
    ubyte[8] header;
    auto first = source.readRange(0, header.length, header[]);
    assert(first.ok && first.bytes == 8);
    assert(header[0] == 'I' && header[1] == 'I');

    ubyte[32] ifd;
    auto second = source.readRange(8, ifd.length, ifd[]);
    assert(second.ok && second.bytes == 32);
    assert(source.requests == 2);
    assert(source.requestedBytes == 40);

    RangeMetrics metrics = RangeMetrics(source.requests, source.requestedBytes, 84);
    assert(metrics.amplification > 2.0);

    ubyte[4] tooShort;
    auto rejected = source.readRange(input.length, 1, tooShort[]);
    assert(!rejected.ok);
    assert(source.requests == 2);
    writefln("local ranges: requests=%s encoded=%s decoded=%s amplification=%.2f file=%s",
        metrics.requests, metrics.encodedBytes, metrics.decodedBytes,
        metrics.amplification, input.length);
}
