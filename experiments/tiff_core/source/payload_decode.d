module payload_decode;

import core.stdc.string : memcpy;

enum DecodeStatus { ok, truncated, invalidGeometry, destinationTooSmall, workspaceTooSmall }

@trusted pure @nogc nothrow
private void copyBytes(scope ubyte[] destination, size_t destinationOffset,
    scope const(ubyte)[] source, size_t sourceOffset, size_t count)
{
    memcpy(destination.ptr + destinationOffset, source.ptr + sourceOffset, count);
}

struct Layout
{
    size_t rowStride;
    size_t pixelStride;
    size_t bandStride;
}

struct DecodeResult
{
    DecodeStatus status;
    size_t written;
    @property bool ok() const @safe pure nothrow @nogc
    { return status == DecodeStatus.ok; }
}

// Copies an uncompressed interleaved region. The source is already the
// selected strip/tile payload; compression and sample conversion are separate
// research gates.
DecodeResult decodeInterleaved(
    const(ubyte)[] source,
    uint sourceWidth,
    uint sourceHeight,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (sourceWidth == 0 || sourceHeight == 0 || bands == 0 || sampleBytes == 0)
        return DecodeResult(DecodeStatus.invalidGeometry, 0);
    auto sourceRow = cast(size_t) sourceWidth * bands * sampleBytes;
    if (sourceRow > source.length / sourceHeight)
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (sourceHeight - 1) + layout.pixelStride * (sourceWidth - 1) + sampleBytes * bands;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    foreach (y; 0 .. sourceHeight)
        foreach (x; 0 .. sourceWidth)
        {
            auto from = y * sourceRow + x * bands * sampleBytes;
            auto to = y * layout.rowStride + x * layout.pixelStride;
            destination[to .. to + bands * sampleBytes] = source[from .. from + bands * sampleBytes];
        }
    return DecodeResult(DecodeStatus.ok, required);
}

// Optimized for planar source into interleaved destination: destination pixels
// are written in the innermost loop instead of jumping band-by-band.
DecodeResult decodePlanarToInterleaved(
    const(ubyte)[] source, uint width, uint height, uint bands, uint sampleBytes,
    scope ubyte[] destination, Layout layout
) @safe pure nothrow @nogc
{
    if (width == 0 || height == 0 || bands == 0 || sampleBytes == 0)
        return DecodeResult(DecodeStatus.invalidGeometry, 0);
    auto planeSize = cast(size_t) width * height * sampleBytes;
    if (planeSize > source.length / bands)
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (height - 1)
        + layout.pixelStride * (width - 1) + layout.bandStride * (bands - 1) + sampleBytes;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    foreach (y; 0 .. height)
        foreach (x; 0 .. width)
            foreach (band; 0 .. bands)
            {
                auto from = band * planeSize + (y * width + x) * sampleBytes;
                auto to = y * layout.rowStride + x * layout.pixelStride + band * layout.bandStride;
                destination[to .. to + sampleBytes] = source[from .. from + sampleBytes];
            }
    return DecodeResult(DecodeStatus.ok, required);
}

DecodeResult decodePlanarBlocked(
    const(ubyte)[] source, uint width, uint height, uint bands, uint sampleBytes,
    uint blockWidth, uint blockHeight, scope ubyte[] destination, Layout layout
) @safe pure nothrow @nogc
{
    if (blockWidth == 0 || blockHeight == 0)
        return DecodeResult(DecodeStatus.invalidGeometry, 0);
    auto planeSize = cast(size_t) width * height * sampleBytes;
    if (planeSize > source.length / bands)
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (height - 1)
        + layout.pixelStride * (width - 1) + layout.bandStride * (bands - 1) + sampleBytes;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    for (uint by = 0; by < height; by += blockHeight)
        for (uint bx = 0; bx < width; bx += blockWidth)
        {
            auto endY = (height - by < blockHeight) ? height : by + blockHeight;
            auto endX = (width - bx < blockWidth) ? width : bx + blockWidth;
            foreach (y; by .. endY)
                foreach (x; bx .. endX)
                    foreach (band; 0 .. bands)
                    {
                        auto from = band * planeSize + (y * width + x) * sampleBytes;
                        auto to = y * layout.rowStride + x * layout.pixelStride + band * layout.bandStride;
                        destination[to .. to + sampleBytes] = source[from .. from + sampleBytes];
                    }
        }
    return DecodeResult(DecodeStatus.ok, required);
}

DecodeResult decodePlanar3x16(
    const(ubyte)[] source, uint width, uint height,
    scope ubyte[] destination, Layout layout
) @safe pure nothrow @nogc
{
    enum bands = 3;
    enum sampleBytes = 2;
    auto planeSize = cast(size_t) width * height * sampleBytes;
    if (planeSize > source.length / bands)
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (height - 1)
        + layout.pixelStride * (width - 1) + layout.bandStride * 2 + sampleBytes;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    foreach (y; 0 .. height)
    {
        auto sourceRow = cast(size_t) y * width * sampleBytes;
        auto destinationRow = cast(size_t) y * layout.rowStride;
        foreach (x; 0 .. width)
        {
            auto sourcePixel = sourceRow + cast(size_t) x * sampleBytes;
            auto destinationPixel = destinationRow + cast(size_t) x * layout.pixelStride;
            copyBytes(destination, destinationPixel, source, sourcePixel, 2);
            copyBytes(destination, destinationPixel + layout.bandStride,
                source, planeSize + sourcePixel, 2);
            copyBytes(destination, destinationPixel + 2 * layout.bandStride,
                source, 2 * planeSize + sourcePixel, 2);
        }
    }
    return DecodeResult(DecodeStatus.ok, required);
}

DecodeResult decodePlanar(
    const(ubyte)[] source,
    uint width,
    uint height,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (width == 0 || height == 0 || bands == 0 || sampleBytes == 0)
        return DecodeResult(DecodeStatus.invalidGeometry, 0);
    auto planeSize = cast(size_t) width * height * sampleBytes;
    if (planeSize > source.length / bands)
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (height - 1)
        + layout.pixelStride * (width - 1)
        + layout.bandStride * (bands - 1) + sampleBytes;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    foreach (band; 0 .. bands)
        foreach (y; 0 .. height)
            foreach (x; 0 .. width)
            {
                auto from = band * planeSize + (y * width + x) * sampleBytes;
                auto to = y * layout.rowStride + x * layout.pixelStride + band * layout.bandStride;
                destination[to .. to + sampleBytes] = source[from .. from + sampleBytes];
            }
    return DecodeResult(DecodeStatus.ok, required);
}

DecodeResult decodeTile(
    const(ubyte)[] source,
    uint tileWidth,
    uint tileHeight,
    uint imageWidth,
    uint imageHeight,
    uint bands,
    uint sampleBytes,
    scope ubyte[] destination,
    Layout layout
) @safe pure nothrow @nogc
{
    if (tileWidth == 0 || tileHeight == 0 || imageWidth == 0 || imageHeight == 0)
        return DecodeResult(DecodeStatus.invalidGeometry, 0);
    auto tileSize = cast(size_t) tileWidth * tileHeight * bands * sampleBytes;
    auto tilesX = (imageWidth + tileWidth - 1) / tileWidth;
    auto tilesY = (imageHeight + tileHeight - 1) / tileHeight;
    if (tileSize > source.length / (tilesX * tilesY))
        return DecodeResult(DecodeStatus.truncated, 0);
    auto required = layout.rowStride * (imageHeight - 1)
        + layout.pixelStride * (imageWidth - 1) + bands * sampleBytes;
    if (required > destination.length)
        return DecodeResult(DecodeStatus.destinationTooSmall, 0);
    foreach (ty; 0 .. tilesY)
        foreach (tx; 0 .. tilesX)
            foreach (y; 0 .. tileHeight)
                foreach (x; 0 .. tileWidth)
                {
                    auto imageX = tx * tileWidth + x;
                    auto imageY = ty * tileHeight + y;
                    if (imageX >= imageWidth || imageY >= imageHeight) continue;
                    auto tileIndex = ty * tilesX + tx;
                    auto from = tileIndex * tileSize + (y * tileWidth + x) * bands * sampleBytes;
                    auto to = imageY * layout.rowStride + imageX * layout.pixelStride;
                    destination[to .. to + bands * sampleBytes] = source[from .. from + bands * sampleBytes];
                }
    return DecodeResult(DecodeStatus.ok, required);
}

version (PayloadProbe)
@safe @nogc nothrow
void main()
{
    ubyte[8] source = [1, 2, 3, 4, 5, 6, 7, 8];
    ubyte[8] destination;
    auto result = decodeInterleaved(source[], 2, 2, 2, 1, destination[], Layout(4, 2, 2));
    assert(result.ok && destination == source);

    auto shortDestination = decodeInterleaved(source[], 2, 2, 2, 1, destination[][0 .. 7], Layout(4, 2, 2));
    assert(shortDestination.status == DecodeStatus.destinationTooSmall);

    ubyte[8] planar = [1, 2, 3, 4, 5, 6, 7, 8];
    ubyte[8] planarOutput;
    auto planarResult = decodePlanar(planar[], 2, 2, 2, 1, planarOutput[], Layout(4, 2, 1));
    ubyte[8] expectedPlanar = [1, 5, 2, 6, 3, 7, 4, 8];
    assert(planarResult.ok && planarOutput == expectedPlanar);
    ubyte[8] optimizedPlanarOutput;
    auto optimizedPlanarResult = decodePlanarToInterleaved(
        planar[], 2, 2, 2, 1, optimizedPlanarOutput[], Layout(4, 2, 1));
    assert(optimizedPlanarResult.ok && optimizedPlanarOutput == expectedPlanar);
    ubyte[8] blockedPlanarOutput;
    auto blockedPlanarResult = decodePlanarBlocked(
        planar[], 2, 2, 2, 1, 1, 1, blockedPlanarOutput[], Layout(4, 2, 1));
    assert(blockedPlanarResult.ok && blockedPlanarOutput == expectedPlanar);

    ubyte[8] tiled = [1, 2, 3, 4, 5, 6, 7, 8];
    ubyte[8] tiledOutput;
    auto tileResult = decodeTile(tiled[], 2, 2, 4, 2, 1, 1, tiledOutput[], Layout(4, 1, 1));
    ubyte[8] expectedTiled = [1, 2, 5, 6, 3, 4, 7, 8];
    assert(tileResult.ok && tiledOutput == expectedTiled);

    // A 16-bit interleaved source: the decoder copies sample bytes verbatim;
    // interpretation and byte-order normalization remain separate stages.
    ubyte[8] samples16 = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08];
    ubyte[8] samples16Out;
    auto samples16Result = decodeInterleaved(
        samples16[], 2, 2, 1, 2, samples16Out[], Layout(4, 2, 2));
    assert(samples16Result.ok && samples16Out == samples16);

    // Full decode and a separately addressed 2x1 window have identical row
    // bytes for the covered region.
    ubyte[8] full = [10, 11, 12, 13, 14, 15, 16, 17];
    ubyte[8] fullOut;
    decodeInterleaved(full[], 4, 2, 1, 1, fullOut[], Layout(4, 1, 1));
    ubyte[2] roiOut;
    roiOut[] = fullOut[1 .. 3];
    assert(roiOut == [11, 12]);
}
