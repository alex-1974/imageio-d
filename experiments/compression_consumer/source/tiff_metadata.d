/// Bounded metadata adapter for this consumer corpus, not a general TIFF API.
module tiff_metadata;
import ifd_result : TagValue;
import deflate_bridge;

// The older experiment's Reader methods do not borrow `this` with `scope`.
// Keep this borrowing cursor local rather than weakening the consumer probe.
private struct Reader
{
    const(ubyte)[] bytes;
    bool little;
    @safe pure nothrow @nogc:
    bool has(size_t p, size_t n) const scope { return p <= bytes.length && n <= bytes.length - p; }
    ushort u16(size_t p) const scope
    { return little ? cast(ushort)(bytes[p] | bytes[p+1] << 8) : cast(ushort)(bytes[p] << 8 | bytes[p+1]); }
    uint u32(size_t p) const scope
    { return little ? cast(uint)(bytes[p] | bytes[p+1] << 8 | bytes[p+2] << 16 | bytes[p+3] << 24) :
        cast(uint)(bytes[p] << 24 | bytes[p+1] << 16 | bytes[p+2] << 8 | bytes[p+3]); }
}

struct TiffInfo
{
    ImageSpec spec;
    TagValue offsets, counts;
}

private bool item(scope Reader r, TagValue tag, uint index, out uint value) @safe pure nothrow @nogc
{
    if ((tag.type != 3 && tag.type != 4) || index >= tag.count) return false;
    const width = tag.type == 3 ? 2U : 4U;
    const inlineData = cast(ulong)tag.count * width <= 4;
    if (inlineData)
    {
        const shift = r.little ? index * width * 8 : (4 - width - index * width) * 8;
        value = (tag.inlineValue >> shift) & (width == 2 ? 65535 : uint.max);
        return true;
    }
    const offset = cast(ulong)tag.valueOffset + cast(ulong)index * width;
    if (offset > size_t.max || !r.has(cast(size_t)offset, width)) return false;
    value = width == 2 ? r.u16(cast(size_t)offset) : r.u32(cast(size_t)offset);
    return true;
}

BridgeStatus inspectTiff(scope const(ubyte)[] file, out TiffInfo info) @safe pure nothrow @nogc
{
    if (file.length < 8) return BridgeStatus.truncated;
    if (!((file[0] == 'I' && file[1] == 'I') || (file[0] == 'M' && file[1] == 'M')))
        return BridgeStatus.invalidMetadata;
    Reader r = Reader(file, file[0] == 'I');
    if (r.u16(2) != 42) return BridgeStatus.unsupported;
    size_t ifd = r.u32(4);
    if (!r.has(ifd, 2)) return BridgeStatus.truncated;
    const count = r.u16(ifd);
    if (count > (size_t.max - ifd - 2) / 12 || !r.has(ifd + 2, cast(size_t)count * 12 + 4))
        return BridgeStatus.truncated;
    ImageSpec s;
    s.bands = 1; s.predictor = 1; s.littleEndian = r.little;
    uint compression, planar = 1, rows = uint.max, tileWidth, tileHeight;
    TagValue bits, sampleFormat, strips, stripCounts, tiles, tileCounts;
    bool[16] seen;
    foreach (uint i; 0 .. count)
    {
        const p = ifd + 2 + cast(size_t)i * 12;
        const t = TagValue(r.u16(p), r.u16(p + 2), r.u32(p + 4), r.u32(p + 8), r.u32(p + 8));
        uint key;
        switch (t.tag)
        {
        case 256: key = 1; break; case 257: key = 2; break; case 258: key = 3; break;
        case 259: key = 4; break; case 277: key = 5; break; case 278: key = 6; break;
        case 284: key = 7; break; case 317: key = 8; break; case 322: key = 9; break;
        case 323: key = 10; break; case 273: key = 11; break; case 279: key = 12; break;
        case 324: key = 13; break; case 325: key = 14; break;
        case 339:
            if (seen[15]) return BridgeStatus.invalidMetadata;
            seen[15] = true; sampleFormat = t; continue;
        default: continue;
        }
        if (seen[key]) return BridgeStatus.invalidMetadata;
        seen[key] = true;
        uint value;
        if (key != 3 && key < 11 && (t.count != 1 || !item(r, t, 0, value)))
            return BridgeStatus.invalidMetadata;
        switch (key)
        {
        case 1: s.width = value; break; case 2: s.height = value; break;
        case 3: bits = t; break; case 4: compression = value; break;
        case 5: s.bands = value; break; case 6: rows = value; break;
        case 7: planar = value; break; case 8: s.predictor = value; break;
        case 9: tileWidth = value; break; case 10: tileHeight = value; break;
        case 11: strips = t; break; case 12: stripCounts = t; break;
        case 13: tiles = t; break; case 14: tileCounts = t; break;
        default: assert(0);
        }
    }
    if ((compression != 8 && compression != 32946) || planar != 1) return BridgeStatus.unsupported;
    if (!bits.count || (bits.count != 1 && bits.count != s.bands)) return BridgeStatus.unsupported;
    uint depth;
    foreach (uint i; 0 .. bits.count)
    {
        uint value;
        if (!item(r, bits, i, value)) return BridgeStatus.truncated;
        if ((value != 8 && value != 16) || (i && value != depth)) return BridgeStatus.unsupported;
        depth = value;
    }
    if (sampleFormat.count != 0)
    {
        if (sampleFormat.count != 1 && sampleFormat.count != s.bands) return BridgeStatus.unsupported;
        foreach (uint i; 0 .. sampleFormat.count)
        {
            uint value;
            if (!item(r, sampleFormat, i, value)) return BridgeStatus.truncated;
            if (value != 1) return BridgeStatus.unsupported;
        }
    }
    s.sampleBytes = depth / 8;
    s.tiled = tiles.count != 0;
    if (s.tiled && strips.count) return BridgeStatus.invalidMetadata;
    s.blockWidth = s.tiled ? tileWidth : s.width;
    s.blockHeight = s.tiled ? tileHeight : rows;
    const offsets = s.tiled ? tiles : strips;
    const counts = s.tiled ? tileCounts : stripCounts;
    const req = requirements(s);
    if (req.status != BridgeStatus.ok) return req.status;
    if (offsets.count != req.blockCount || counts.count != req.blockCount) return BridgeStatus.invalidMetadata;
    info = TiffInfo(s, offsets, counts);
    return BridgeStatus.ok;
}

BridgeStatus readBlocks(scope const(ubyte)[] file, TiffInfo info,
    scope Block[] blocks) @safe pure nothrow @nogc
{
    if (blocks.length != info.offsets.count) return BridgeStatus.invalidMetadata;
    Reader r = Reader(file, info.spec.littleEndian);
    foreach (uint i; 0 .. info.offsets.count)
    {
        uint offset, count;
        if (!item(r, info.offsets, i, offset) || !item(r, info.counts, i, count)) return BridgeStatus.truncated;
        blocks[i] = Block(offset, count);
    }
    return BridgeStatus.ok;
}
