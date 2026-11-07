module strip_bridge;

import payload_decode : DecodeResult, DecodeStatus, Layout, decodeInterleaved;

struct Strip
{
    uint offset;
    uint byteCount;
}

DecodeResult decodeStrip(
    const(ubyte)[] fileBytes,
    Strip strip,
    uint width,
    uint height,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    auto start = cast(size_t) strip.offset;
    auto length = cast(size_t) strip.byteCount;
    if (start > fileBytes.length || length > fileBytes.length - start)
        return DecodeResult(DecodeStatus.truncated, 0);
    return decodeInterleaved(
        fileBytes[start .. start + length],
        width,
        height,
        bands,
        sampleBytes,
        destination,
        layout
    );
}

@safe @nogc nothrow
void main()
{
    ubyte[16] fileBytes;
    ubyte[8] payload = [1, 2, 3, 4, 5, 6, 7, 8];
    fileBytes[8 .. 16] = payload[];
    ubyte[8] output;
    auto result = decodeStrip(
        fileBytes[], Strip(8, 8), 2, 2, 2, 1, output[], Layout(4, 2, 2));
    assert(result.ok && output == [1, 2, 3, 4, 5, 6, 7, 8]);

    auto invalid = decodeStrip(
        fileBytes[], Strip(12, 8), 2, 2, 2, 1, output[], Layout(4, 2, 2));
    assert(invalid.status == DecodeStatus.truncated);
}
