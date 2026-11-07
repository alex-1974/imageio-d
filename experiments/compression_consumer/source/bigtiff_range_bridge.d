/// BigTIFF research bridge over separately supplied compressed byte windows.
module bigtiff_range_bridge;

import bigtiff_header : RangeWindow;
import deflate_bridge : ImageSpec, BridgeStatus, BridgeResult, requirements,
    decodeDeflateBlocks, Layout, Block;
import compression.deflate : InflateWorkspace;
import compression.core : ErrorCode;

struct Block64 { ulong offset, byteCount; }

/// Stages a complete verified block in caller storage before committing pixels.
BridgeResult decodeDeflateRanges(scope const(Block64)[] blocks,
    scope const(RangeWindow)[] windows, ImageSpec spec,
    ref InflateWorkspace decoder, scope ubyte[] inflateScratch,
    scope ubyte[] blockPixels, scope ubyte[] destination, Layout layout)
    @safe pure nothrow @nogc
{
    auto req = requirements(spec);
    if (req.status != BridgeStatus.ok) return BridgeResult(req.status);
    if (blocks.length != req.blockCount) return BridgeResult(BridgeStatus.invalidMetadata);
    if (inflateScratch.length < req.scratchBytes || blockPixels.length < req.scratchBytes)
        return BridgeResult(BridgeStatus.workspaceTooSmall);
    auto pixel = cast(size_t)spec.bands * spec.sampleBytes;
    if (layout.pixelStride < pixel || spec.width == 0 || spec.height == 0)
        return BridgeResult(BridgeStatus.invalidMetadata);
    auto rowSpan = cast(size_t)(spec.width - 1);
    if (rowSpan && layout.pixelStride > (size_t.max - pixel) / rowSpan)
        return BridgeResult(BridgeStatus.sizeOverflow);
    rowSpan = rowSpan * layout.pixelStride + pixel;
    if (layout.rowStride < rowSpan) return BridgeResult(BridgeStatus.invalidMetadata);
    auto rows = cast(size_t)(spec.height - 1);
    if (rows && layout.rowStride > (size_t.max - rowSpan) / rows)
        return BridgeResult(BridgeStatus.sizeOverflow);
    if (rows * layout.rowStride + rowSpan > destination.length)
        return BridgeResult(BridgeStatus.destinationTooSmall);
    bool ordered = true;
    ulong previousEnd;
    foreach (i, block; blocks)
    {
        if (!block.byteCount || block.byteCount > uint.max || block.offset > ulong.max - block.byteCount)
            return BridgeResult(BridgeStatus.invalidMetadata);
        if (i && block.offset < previousEnd) ordered = false;
        previousEnd = block.offset + block.byteCount;
        bool found = i < windows.length && windows[i].contains(block.offset, block.byteCount);
        if (!found)
            foreach (window; windows)
                if (window.contains(block.offset, block.byteCount)) { found = true; break; }
        if (!found) return BridgeResult(BridgeStatus.truncated);
    }
    if (!ordered)
        foreach (i, block; blocks)
            foreach (other; blocks[0 .. i])
                if (block.offset < other.offset + other.byteCount &&
                    other.offset < block.offset + block.byteCount)
                    return BridgeResult(BridgeStatus.invalidMetadata);
    auto tilesX = spec.tiled ? (spec.width - 1) / spec.blockWidth + 1 : 1;
    foreach (i, block; blocks)
    {
        const x = cast(uint)(i % tilesX) * spec.blockWidth;
        const y = cast(uint)(i / tilesX) * spec.blockHeight;
        const visibleWidth = spec.width - x < spec.blockWidth ? spec.width - x : spec.blockWidth;
        const visibleRows = spec.height - y < spec.blockHeight ? spec.height - y : spec.blockHeight;
        const decodedRows = spec.tiled ? spec.blockHeight : visibleRows;
        const required = cast(size_t)spec.blockWidth * decodedRows * pixel;
        auto direct = i < windows.length && windows[i].contains(block.offset, block.byteCount);
        foreach (j; 0 .. (direct ? 1 : windows.length))
        {
            auto window = direct ? windows[i] : windows[j];
            if (!window.contains(block.offset, block.byteCount)) continue;
            const start = cast(size_t)(block.offset - window.offset);
            Block[1] compact = [Block(0, cast(uint)block.byteCount)];
            auto one = spec;
            one.width = spec.blockWidth;
            one.height = decodedRows;
            one.tiled = false;
            one.blockHeight = decodedRows;
            auto result = decodeDeflateBlocks(window.bytes[start .. start + cast(size_t)block.byteCount],
                compact[], one, decoder, inflateScratch[0 .. required],
                blockPixels[0 .. required], Layout(spec.blockWidth * pixel, pixel, spec.sampleBytes));
            if (!result.ok) return BridgeResult(result.status, result.codec, i);
            foreach (yy; 0 .. visibleRows)
            foreach (xx; 0 .. visibleWidth)
            {
                auto src = (cast(size_t)yy * spec.blockWidth + xx) * pixel;
                auto dst = (cast(size_t)(y + yy)) * layout.rowStride +
                    (cast(size_t)(x + xx)) * layout.pixelStride;
                destination[dst .. dst + pixel] = blockPixels[src .. src + pixel];
            }
            break;
        }
    }
    return BridgeResult(BridgeStatus.ok, ErrorCode.none, blocks.length);
}
