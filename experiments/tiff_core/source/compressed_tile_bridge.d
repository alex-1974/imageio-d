module compressed_tile_bridge;

import payload_decode : Layout, DecodeStatus, decodeInterleaved;
import block_bridge : Block;
import packbits : decode, Status;

DecodeStatus decodePackBitsTiles(
    const(ubyte)[] fileBytes,
    scope const(Block)[] tiles,
    uint imageWidth,
    uint imageHeight,
    uint tileWidth,
    uint tileHeight,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    scope ubyte[] scratch,
    Layout layout
) @safe nothrow @nogc
{
    if (tileWidth == 0 || tileHeight == 0 || imageWidth == 0 || imageHeight == 0)
        return DecodeStatus.invalidGeometry;
    auto tilesX = (imageWidth + tileWidth - 1) / tileWidth;
    auto tilesY = (imageHeight + tileHeight - 1) / tileHeight;
    if (tilesX * tilesY != tiles.length) return DecodeStatus.invalidGeometry;
    auto bytesPerPixel = cast(size_t) bands * sampleBytes;
    auto requiredDestination = layout.rowStride * (imageHeight - 1)
        + layout.pixelStride * (imageWidth - 1) + bytesPerPixel;
    if (requiredDestination > destination.length)
        return DecodeStatus.destinationTooSmall;
    auto sourceBytes = cast(size_t) tileWidth * tileHeight * bands * sampleBytes;
    if (scratch.length < sourceBytes) return DecodeStatus.workspaceTooSmall;
    foreach (index, tile; tiles)
    {
        auto x = (index % tilesX) * tileWidth;
        auto y = (index / tilesX) * tileHeight;
        auto width = (imageWidth - x < tileWidth) ? imageWidth - x : tileWidth;
        auto height = (imageHeight - y < tileHeight) ? imageHeight - y : tileHeight;
        auto start = cast(size_t) tile.offset;
        auto length = cast(size_t) tile.byteCount;
        if (start > fileBytes.length || length > fileBytes.length - start)
            return DecodeStatus.truncated;
        auto unpacked = scratch[0 .. sourceBytes];
        auto result = decode(fileBytes[start .. start + length], unpacked);
        if (result.status == Status.truncated) return DecodeStatus.truncated;
        if (result.status == Status.destinationTooSmall) return DecodeStatus.workspaceTooSmall;
        if (result.written != sourceBytes) return DecodeStatus.invalidGeometry;
        foreach (yy; 0 .. height)
            foreach (xx; 0 .. width)
            {
                auto from = (cast(size_t) yy * tileWidth + xx) * bands * sampleBytes;
                auto to = (cast(size_t) y + yy) * layout.rowStride
                    + (cast(size_t) x + xx) * layout.pixelStride;
                auto bytes = bytesPerPixel;
                destination[to .. to + bytes] = unpacked[from .. from + bytes];
            }
    }
    return DecodeStatus.ok;
}
