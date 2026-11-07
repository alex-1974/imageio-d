module compressed_strip_bridge;

import payload_decode : Layout, DecodeStatus, decodeInterleaved;
import block_bridge : Block;
import packbits : decode, Status;

DecodeStatus decodePackBitsStrips(
    const(ubyte)[] fileBytes,
    scope const(Block)[] strips,
    uint width,
    uint height,
    uint rowsPerStrip,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    scope ubyte[] scratch,
    Layout layout
) @safe nothrow @nogc
{
    if (rowsPerStrip == 0 || strips.length == 0)
        return DecodeStatus.invalidGeometry;
    auto rowBytes = cast(size_t) width * bands * sampleBytes;
    foreach (index, strip; strips)
    {
        auto firstRow = index * rowsPerStrip;
        if (firstRow >= height) break;
        auto rows = (height - firstRow < rowsPerStrip) ? height - firstRow : rowsPerStrip;
        auto decodedBytes = cast(size_t) rows * rowBytes;
        auto start = cast(size_t) strip.offset;
        auto length = cast(size_t) strip.byteCount;
        if (start > fileBytes.length || length > fileBytes.length - start)
            return DecodeStatus.truncated;
        if (scratch.length < decodedBytes) return DecodeStatus.workspaceTooSmall;
        auto unpacked = scratch[0 .. decodedBytes];
        auto unpackedResult = decode(fileBytes[start .. start + length], unpacked);
        if (unpackedResult.status == Status.truncated) return DecodeStatus.truncated;
        if (unpackedResult.status == Status.destinationTooSmall)
            return DecodeStatus.workspaceTooSmall;
        if (unpackedResult.written != decodedBytes) return DecodeStatus.invalidGeometry;
        auto target = destination[firstRow * layout.rowStride .. $];
        auto result = decodeInterleaved(unpacked[], width, cast(uint) rows, bands,
            sampleBytes, target, layout);
        if (!result.ok) return result.status;
    }
    return DecodeStatus.ok;
}
