module block_bridge;

import payload_decode : DecodeResult, DecodeStatus, Layout, decodeInterleaved, decodeTile;

struct Block
{
    uint offset;
    uint byteCount;
}

DecodeStatus validateBlocks(
    size_t fileLength, scope const(Block)[] blocks
) @safe pure nothrow @nogc
{
    foreach (i, block; blocks)
    {
        auto start = cast(size_t) block.offset;
        auto length = cast(size_t) block.byteCount;
        if (start > fileLength || length > fileLength - start)
            return DecodeStatus.truncated;
        foreach (j; 0 .. i)
        {
            auto otherStart = cast(size_t) blocks[j].offset;
            auto otherLength = cast(size_t) blocks[j].byteCount;
            auto end = start + length;
            auto otherEnd = otherStart + otherLength;
            if (start < otherEnd && otherStart < end)
                return DecodeStatus.invalidGeometry;
        }
    }
    return DecodeStatus.ok;
}

DecodeStatus decodeTiles(
    const(ubyte)[] fileBytes,
    scope const(Block)[] tiles,
    uint imageWidth,
    uint imageHeight,
    uint tileWidth,
    uint tileHeight,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (tileWidth == 0 || tileHeight == 0 || imageWidth == 0 || imageHeight == 0)
        return DecodeStatus.invalidGeometry;
    auto tilesX = (imageWidth + tileWidth - 1) / tileWidth;
    auto tilesY = (imageHeight + tileHeight - 1) / tileHeight;
    if (tilesX * tilesY != tiles.length)
        return DecodeStatus.invalidGeometry;
    foreach (index, tile; tiles)
    {
        auto tx = index % tilesX;
        auto ty = index / tilesX;
        auto x = tx * tileWidth;
        auto y = ty * tileHeight;
        auto width = (imageWidth - x < tileWidth) ? imageWidth - x : tileWidth;
        auto height = (imageHeight - y < tileHeight) ? imageHeight - y : tileHeight;
        auto start = cast(size_t) tile.offset;
        auto length = cast(size_t) tile.byteCount;
        if (start > fileBytes.length || length > fileBytes.length - start)
            return DecodeStatus.truncated;
        auto sourceRow = cast(size_t) tileWidth * bands * sampleBytes;
        auto pixelBytes = cast(size_t) bands * sampleBytes;
        if (sourceRow > 0 && sourceRow > length / tileHeight)
            return DecodeStatus.truncated;
        foreach (yy; 0 .. height)
            foreach (xx; 0 .. width)
            {
                auto sourceOffset = cast(size_t) yy * sourceRow + xx * pixelBytes;
                auto destinationOffset = (cast(size_t) y + yy) * layout.rowStride
                    + (cast(size_t) x + xx) * layout.pixelStride;
                if (destinationOffset > destination.length
                    || pixelBytes > destination.length - destinationOffset
                    || sourceOffset > length || pixelBytes > length - sourceOffset)
                    return DecodeStatus.destinationTooSmall;
                destination[destinationOffset .. destinationOffset + pixelBytes]
                    = fileBytes[start + sourceOffset .. start + sourceOffset + pixelBytes];
            }
    }
    return DecodeStatus.ok;
}

DecodeStatus decodeStrips(
    const(ubyte)[] fileBytes,
    scope const(Block)[] strips,
    uint width,
    uint height,
    uint rowsPerStrip,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (rowsPerStrip == 0 || strips.length == 0)
        return DecodeStatus.invalidGeometry;
    foreach (index, strip; strips)
    {
        auto firstRow = index * rowsPerStrip;
        if (firstRow >= height) break;
        auto rows = (height - firstRow < rowsPerStrip) ? height - firstRow : rowsPerStrip;
        auto start = cast(size_t) strip.offset;
        auto length = cast(size_t) strip.byteCount;
        if (start > fileBytes.length || length > fileBytes.length - start)
            return DecodeStatus.truncated;
        auto target = destination[firstRow * layout.rowStride .. $];
        auto result = decodeInterleaved(
            fileBytes[start .. start + length], width, cast(uint) rows, bands, sampleBytes,
            target, layout
        );
        if (!result.ok) return result.status;
    }
    return DecodeStatus.ok;
}

// TIFF PlanarConfiguration=2 stores every band's strips consecutively.
// Copy each strip directly from the encoded file into caller-owned
// interleaved storage; no full planar staging buffer is required.
DecodeStatus decodePlanarStrips(
    const(ubyte)[] fileBytes,
    scope const(Block)[] strips,
    uint width,
    uint height,
    uint rowsPerStrip,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (width == 0 || height == 0 || rowsPerStrip == 0 || bands == 0
        || sampleBytes == 0)
        return DecodeStatus.invalidGeometry;
    const stripsPerPlane = (cast(size_t) height + rowsPerStrip - 1)
        / rowsPerStrip;
    if (stripsPerPlane > size_t.max / bands
        || strips.length != stripsPerPlane * bands)
        return DecodeStatus.invalidGeometry;
    const blockStatus = validateBlocks(fileBytes.length, strips);
    if (blockStatus != DecodeStatus.ok) return blockStatus;
    if (width > size_t.max / sampleBytes)
        return DecodeStatus.invalidGeometry;
    const sourceRowBytes = cast(size_t) width * sampleBytes;
    if (height > 1 && layout.rowStride > size_t.max / (height - 1)
        || width > 1 && layout.pixelStride > size_t.max / (width - 1)
        || bands > 1 && layout.bandStride > size_t.max / (bands - 1))
        return DecodeStatus.invalidGeometry;
    const lastRow = cast(size_t)(height - 1) * layout.rowStride;
    const lastPixel = cast(size_t)(width - 1) * layout.pixelStride;
    const lastBand = cast(size_t)(bands - 1) * layout.bandStride;
    if (lastRow > size_t.max - lastPixel
        || lastRow + lastPixel > size_t.max - lastBand
        || lastRow + lastPixel + lastBand > size_t.max - sampleBytes
        || lastRow + lastPixel + lastBand + sampleBytes > destination.length)
        return DecodeStatus.destinationTooSmall;

    // Preflight every source payload before committing destination bytes.
    foreach (band; 0 .. bands)
        foreach (stripInPlane; 0 .. stripsPerPlane)
        {
            const firstRow = stripInPlane * rowsPerStrip;
            const rows = height - firstRow < rowsPerStrip
                ? height - firstRow : rowsPerStrip;
            if (rows > size_t.max / sourceRowBytes
                || strips[band * stripsPerPlane + stripInPlane].byteCount
                    < rows * sourceRowBytes)
                return DecodeStatus.truncated;
        }

    foreach (band; 0 .. bands)
        foreach (stripInPlane; 0 .. stripsPerPlane)
        {
            const block = strips[band * stripsPerPlane + stripInPlane];
            const firstRow = stripInPlane * rowsPerStrip;
            const rows = height - firstRow < rowsPerStrip
                ? height - firstRow : rowsPerStrip;
            foreach (row; 0 .. rows)
                foreach (x; 0 .. width)
                    foreach (byteIndex; 0 .. sampleBytes)
                    {
                        const sourceOffset = cast(size_t) block.offset
                            + row * sourceRowBytes + x * sampleBytes + byteIndex;
                        const destinationOffset = (firstRow + row) * layout.rowStride
                            + x * layout.pixelStride + band * layout.bandStride
                            + byteIndex;
                        destination[destinationOffset] = fileBytes[sourceOffset];
                    }
        }
    return DecodeStatus.ok;
}

version (BlockProbe)
@safe @nogc nothrow
void main()
{
    ubyte[16] fileBytes;
    ubyte[8] first = [1, 2, 3, 4, 5, 6, 7, 8];
    ubyte[8] second = [9, 10, 11, 12, 13, 14, 15, 16];
    fileBytes[0 .. 8] = first[];
    fileBytes[8 .. 16] = second[];
    Block[2] strips = [Block(0, 8), Block(8, 8)];
    ubyte[16] output;
    auto status = decodeStrips(fileBytes[], strips[], 2, 4, 2, 2, 1, output[], Layout(4, 2, 2));
    assert(status == DecodeStatus.ok);
    assert(output == fileBytes);

    ubyte[8] tileBytes = [21, 22, 23, 24, 25, 26, 27, 28];
    Block[2] tiles = [Block(0, 4), Block(4, 4)];
    ubyte[8] tileOutput;
    auto tileStatus = decodeTiles(
        tileBytes[], tiles[], 4, 2, 2, 2, 1, 1, tileOutput[], Layout(4, 1, 1));
    assert(tileStatus == DecodeStatus.ok);
    assert(tileOutput == [21, 22, 25, 26, 23, 24, 27, 28]);

    Block[1] wrongTileCount = [Block(0, 4)];
    assert(decodeTiles(tileBytes[], wrongTileCount[], 4, 2, 2, 2, 1, 1,
        tileOutput[], Layout(4, 1, 1)) == DecodeStatus.invalidGeometry);
    Block[2] truncatedTiles = [Block(0, 4), Block(7, 4)];
    assert(decodeTiles(tileBytes[], truncatedTiles[], 4, 2, 2, 2, 1, 1,
        tileOutput[], Layout(4, 1, 1)) == DecodeStatus.truncated);
    assert(validateBlocks(16, strips[]) == DecodeStatus.ok);
    Block[2] overlap = [Block(0, 5), Block(4, 4)];
    assert(validateBlocks(16, overlap[]) == DecodeStatus.invalidGeometry);
    Block[1] outside = [Block(15, 4)];
    assert(validateBlocks(16, outside[]) == DecodeStatus.truncated);

    // Two bands, two one-row strips per band, converted to interleaved output.
    ubyte[8] planarStripBytes = [1, 2, 3, 4, 11, 12, 13, 14];
    Block[4] planarStrips = [Block(0, 2), Block(2, 2),
        Block(4, 2), Block(6, 2)];
    ubyte[8] planarStripOutput;
    assert(decodePlanarStrips(planarStripBytes[], planarStrips[], 2, 2, 1,
        2, 1, planarStripOutput[], Layout(4, 2, 1)) == DecodeStatus.ok);
    assert(planarStripOutput == [1, 11, 2, 12, 3, 13, 4, 14]);
    assert(decodePlanarStrips(planarStripBytes[], planarStrips[0 .. 3], 2, 2,
        1, 2, 1, planarStripOutput[], Layout(4, 2, 1)) ==
        DecodeStatus.invalidGeometry);
    planarStrips[3].byteCount = 1;
    assert(decodePlanarStrips(planarStripBytes[], planarStrips[], 2, 2, 1,
        2, 1, planarStripOutput[], Layout(4, 2, 1)) == DecodeStatus.truncated);
    planarStrips[3] = Block(5, 2);
    assert(decodePlanarStrips(planarStripBytes[], planarStrips[], 2, 2, 1,
        2, 1, planarStripOutput[], Layout(4, 2, 1)) ==
        DecodeStatus.invalidGeometry);
    planarStrips[3] = Block(6, 2);
    ubyte[7] shortPlanarDestination;
    assert(decodePlanarStrips(planarStripBytes[], planarStrips[], 2, 2, 1,
        2, 1, shortPlanarDestination[], Layout(4, 2, 1)) ==
        DecodeStatus.destinationTooSmall);
}
