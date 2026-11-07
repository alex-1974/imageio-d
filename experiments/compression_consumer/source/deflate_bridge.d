/// Research-only TIFF Deflate adapter. No imageio-d production API admission.
module deflate_bridge;
import compression.core : DecodeLimits, ErrorCode, CodecStatus = DecodeStatus;
import compression.deflate : InflateWorkspace;
import compression.zlib : inflateZlib;
public import payload_decode : Layout;
public import block_bridge : Block;

enum BridgeStatus : ubyte
{
    invalidMetadata, ok, truncated, destinationTooSmall, workspaceTooSmall,
    sizeOverflow, codecError, decodedSizeMismatch, unsupported,
}
struct BridgeResult
{
    BridgeStatus status;
    ErrorCode codec = ErrorCode.none;
    size_t blocksWritten;
    @property bool ok() const @safe pure nothrow @nogc { return status == BridgeStatus.ok; }
}
struct ImageSpec
{
    uint width, height, bands, sampleBytes, blockWidth, blockHeight;
    bool tiled;
    bool littleEndian = true;
    uint predictor = 1;
}
struct Requirements
{
    BridgeStatus status;
    size_t scratchBytes, outputBytes, blockCount;
    enum decoderBytes = InflateWorkspace.sizeof;
}

struct PixelWindow
{
    uint x, y, width, height;
}

enum DecodePath : ubyte { nativeBlocks, fullDecode }

struct WindowReport
{
    DecodePath path;
    uint decodedX, decodedY, decodedWidth, decodedHeight;
    size_t compressedBytes;
    size_t decodedBlocks;
}

private bool multiply(ref size_t value, size_t factor) @safe pure nothrow @nogc
{
    if (value != 0 && factor > size_t.max / value) return false;
    value *= factor;
    return true;
}

Requirements requirements(ImageSpec s) @safe pure nothrow @nogc
{
    if (!s.width || !s.height || !s.bands || !s.blockWidth || !s.blockHeight)
        return Requirements(BridgeStatus.invalidMetadata);
    if ((s.sampleBytes != 1 && s.sampleBytes != 2) || (s.predictor != 1 && s.predictor != 2))
        return Requirements(BridgeStatus.unsupported);
    if (!s.tiled && s.blockWidth != s.width) return Requirements(BridgeStatus.invalidMetadata);
    size_t pixel = s.bands;
    size_t scratch = s.blockWidth;
    size_t output = s.width;
    size_t count = (s.height - 1) / s.blockHeight + 1;
    const rows = s.tiled || s.blockHeight <= s.height ? s.blockHeight : s.height;
    if (!multiply(pixel, s.sampleBytes) || !multiply(scratch, rows) ||
        !multiply(scratch, pixel) || !multiply(output, s.height) || !multiply(output, pixel) ||
        (s.tiled && !multiply(count, (s.width - 1) / s.blockWidth + 1)))
        return Requirements(BridgeStatus.sizeOverflow);
    return Requirements(BridgeStatus.ok, scratch, output, count);
}

private void undoPredictor(scope ubyte[] bytes, size_t width, size_t rows,
    ImageSpec s) @safe pure nothrow @nogc
{
    if (s.predictor != 2) return;
    const pixel = cast(size_t)s.bands * s.sampleBytes;
    const row = width * pixel;
    foreach (y; 0 .. rows)
    foreach (i; pixel .. row)
    {
        const current = y * row + i;
        const previous = current - pixel;
        if (s.sampleBytes == 1)
            bytes[current] += bytes[previous];
        else if ((i % 2) == 0)
        {
            uint value = s.littleEndian ? bytes[current] | (bytes[current + 1] << 8) :
                (bytes[current] << 8) | bytes[current + 1];
            const left = s.littleEndian ? bytes[previous] | (bytes[previous + 1] << 8) :
                (bytes[previous] << 8) | bytes[previous + 1];
            value += left;
            bytes[current] = cast(ubyte)(s.littleEndian ? value : value >> 8);
            bytes[current + 1] = cast(ubyte)(s.littleEndian ? value >> 8 : value);
        }
    }
}

/** Every compressed block is verified into scratch before its visible pixels
    are committed. On error earlier blocks remain, the failing block is untouched.
    Scratch may be overwritten. Separate workspaces are required concurrently. */
BridgeResult decodeDeflateBlocks(scope const(ubyte)[] file, scope const(Block)[] blocks,
    ImageSpec s, ref InflateWorkspace decoder, scope ubyte[] scratch,
    scope ubyte[] destination, Layout layout) @safe pure nothrow @nogc
{
    const r = requirements(s);
    if (r.status != BridgeStatus.ok) return BridgeResult(r.status);
    if (blocks.length != r.blockCount) return BridgeResult(BridgeStatus.invalidMetadata);
    const pixel = cast(size_t)s.bands * s.sampleBytes;
    if (layout.pixelStride < pixel) return BridgeResult(BridgeStatus.invalidMetadata);
    size_t rowSpan = s.width - 1;
    size_t span = s.height - 1;
    if (!multiply(rowSpan, layout.pixelStride) || rowSpan > size_t.max - pixel)
        return BridgeResult(BridgeStatus.sizeOverflow);
    rowSpan += pixel;
    if (layout.rowStride < rowSpan) return BridgeResult(BridgeStatus.invalidMetadata);
    if (!multiply(span, layout.rowStride) || span > size_t.max - rowSpan)
        return BridgeResult(BridgeStatus.sizeOverflow);
    if (span + rowSpan > destination.length) return BridgeResult(BridgeStatus.destinationTooSmall);
    if (scratch.length < r.scratchBytes) return BridgeResult(BridgeStatus.workspaceTooSmall);
    // Preflight all ranges and overlap before changing destination storage.
    bool monotonic = true;
    size_t previousEnd;
    foreach (i, block; blocks)
    {
        size_t offset = block.offset, length = block.byteCount;
        if (offset > file.length || length > file.length - offset) return BridgeResult(BridgeStatus.truncated);
        if (i && offset < previousEnd) monotonic = false;
        previousEnd = offset + length;
    }
    // Linear preflight for normal file-ordered blocks; legal unordered blocks
    // retain the complete overlap check without imposing a sorting allocation.
    if (!monotonic)
        foreach (i, block; blocks)
            foreach (other; blocks[0 .. i])
                if (block.offset < cast(size_t)other.offset + other.byteCount &&
                    other.offset < cast(size_t)block.offset + block.byteCount)
                    return BridgeResult(BridgeStatus.invalidMetadata);
    const tilesX = s.tiled ? (s.width - 1) / s.blockWidth + 1 : 1;
    foreach (i, block; blocks)
    {
        const x = (i % tilesX) * s.blockWidth, y = (i / tilesX) * s.blockHeight;
        const rows = s.height - y < s.blockHeight ? s.height - y : s.blockHeight;
        const columns = s.width - x < s.blockWidth ? s.width - x : s.blockWidth;
        const decodedRows = s.tiled ? s.blockHeight : rows;
        const expected = cast(size_t)s.blockWidth * decodedRows * pixel;
        auto unpacked = scratch[0 .. expected];
        const decoded = inflateZlib(file[block.offset .. cast(size_t)block.offset + block.byteCount],
            unpacked, decoder, DecodeLimits(expected));
        if (decoded.status != CodecStatus.done)
            return BridgeResult(BridgeStatus.codecError, decoded.error.code, i);
        if (decoded.produced != expected || decoded.consumed != block.byteCount)
            return BridgeResult(BridgeStatus.decodedSizeMismatch, ErrorCode.none, i);
        undoPredictor(unpacked, s.blockWidth, decodedRows, s);
        foreach (yy; 0 .. rows)
        foreach (xx; 0 .. columns)
        {
            const source = (yy * s.blockWidth + xx) * pixel;
            const target = (y + yy) * layout.rowStride + (x + xx) * layout.pixelStride;
            destination[target .. target + pixel] = unpacked[source .. source + pixel];
        }
    }
    return BridgeResult(BridgeStatus.ok, ErrorCode.none, blocks.length);
}

/** Decode only tiles intersecting a pixel window into a window-sized,
    caller-owned destination. The block table remains file-complete, but
    non-intersecting compressed blocks are never read or inflated. */
BridgeResult decodeDeflateWindowReported(scope const(ubyte)[] file, scope const(Block)[] blocks,
    ImageSpec s, PixelWindow window, ref InflateWorkspace decoder,
    scope ubyte[] scratch, scope ubyte[] destination, Layout layout,
    out WindowReport report)
    @safe pure nothrow @nogc
{
    report = WindowReport(DecodePath.nativeBlocks, window.x, window.y,
        window.width, window.height, 0, 0);
    const r = requirements(s);
    if (r.status != BridgeStatus.ok || !window.width || !window.height)
        return BridgeResult(r.status == BridgeStatus.ok ? BridgeStatus.invalidMetadata : r.status);
    if (window.x > s.width || window.width > s.width - window.x
        || window.y > s.height || window.height > s.height - window.y)
        return BridgeResult(BridgeStatus.invalidMetadata);
    const pixel = cast(size_t)s.bands * s.sampleBytes;
    if (layout.pixelStride < pixel || layout.rowStride < window.width * layout.pixelStride)
        return BridgeResult(BridgeStatus.invalidMetadata);
    if ((window.height - 1) * layout.rowStride + (window.width - 1) * layout.pixelStride
        + pixel > destination.length)
        return BridgeResult(BridgeStatus.destinationTooSmall);
    if (scratch.length < r.scratchBytes || blocks.length != r.blockCount)
        return BridgeResult(BridgeStatus.workspaceTooSmall);
    const tilesX = s.tiled ? (s.width - 1) / s.blockWidth + 1 : 1;
    size_t decodedBlocks;
    foreach (i, block; blocks)
    {
        const tileX = (i % tilesX) * s.blockWidth;
        const tileY = (i / tilesX) * s.blockHeight;
        const tileW = s.width - tileX < s.blockWidth ? s.width - tileX : s.blockWidth;
        const tileH = s.height - tileY < s.blockHeight ? s.height - tileY : s.blockHeight;
        if (tileX + tileW <= window.x || window.x + window.width <= tileX
            || tileY + tileH <= window.y || window.y + window.height <= tileY)
            continue;
        size_t offset = block.offset, length = block.byteCount;
        if (offset > file.length || length > file.length - offset)
            return BridgeResult(BridgeStatus.truncated, ErrorCode.none, decodedBlocks);
        const expected = cast(size_t)s.blockWidth * s.blockHeight * pixel;
        auto unpacked = scratch[0 .. expected];
        const decoded = inflateZlib(file[offset .. offset + length], unpacked, decoder,
            DecodeLimits(expected));
        if (decoded.status != CodecStatus.done)
            return BridgeResult(BridgeStatus.codecError, decoded.error.code, decodedBlocks);
        if (decoded.produced != expected || decoded.consumed != length)
            return BridgeResult(BridgeStatus.decodedSizeMismatch, ErrorCode.none, decodedBlocks);
        report.compressedBytes += length;
        undoPredictor(unpacked, s.blockWidth, s.blockHeight, s);
        const startX = window.x > tileX ? window.x : tileX;
        const endX = window.x + window.width < tileX + tileW ? window.x + window.width : tileX + tileW;
        const startY = window.y > tileY ? window.y : tileY;
        const endY = window.y + window.height < tileY + tileH ? window.y + window.height : tileY + tileH;
        foreach (yy; startY .. endY)
        foreach (xx; startX .. endX)
        {
            const source = ((yy - tileY) * s.blockWidth + (xx - tileX)) * pixel;
            const target = (yy - window.y) * layout.rowStride + (xx - window.x) * layout.pixelStride;
            destination[target .. target + pixel] = unpacked[source .. source + pixel];
        }
        ++decodedBlocks;
        report.decodedBlocks = decodedBlocks;
    }
    return BridgeResult(BridgeStatus.ok, ErrorCode.none, decodedBlocks);
}

BridgeResult decodeDeflateWindow(scope const(ubyte)[] file, scope const(Block)[] blocks,
    ImageSpec s, PixelWindow window, ref InflateWorkspace decoder,
    scope ubyte[] scratch, scope ubyte[] destination, Layout layout)
    @safe pure nothrow @nogc
{
    WindowReport ignored;
    return decodeDeflateWindowReported(file, blocks, s, window, decoder,
        scratch, destination, layout, ignored);
}
