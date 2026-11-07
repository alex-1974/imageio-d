module tiff_tile_oracle;

import std.file : read;
import std.stdio : writefln;
import std.conv : to;
import ifd_result : parse, Status;
import tag_arrays : readLongArray, readShortArray, ArrayStatus;
import block_bridge : Block, decodeTiles;
import payload_decode : Layout, DecodeStatus;

private void require(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

ulong checksum(const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    ulong value;
    foreach (b; bytes)
        value = value * 131 + b;
    return value;
}

pragma(inline, false)
ulong consume(scope const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    return checksum(bytes);
}

void main(string[] args)
{
    require(args.length == 7 || args.length == 8, "arguments");
    auto tiff = cast(const(ubyte)[]) read(args[1]);
    auto expected = cast(const(ubyte)[]) read(args[2]);
    auto width = to!uint(args[3]);
    auto height = to!uint(args[4]);
    auto tileWidth = to!uint(args[5]);
    auto tileHeight = to!uint(args[6]);
    auto iterations = args.length == 8 ? to!uint(args[7]) : 1;
    auto parsed = parse(tiff);
    require(parsed.status == Status.ok, "TIFF parse");
    require(parsed.value.width == width && parsed.value.height == height,
        "dimensions");
    require(parsed.value.tileOffsets.count == parsed.value.tileByteCounts.count,
        "tile table lengths");
    auto tileCount = parsed.value.tileOffsets.count;
    writefln("tile-count=%s offsets-type=%s counts-type=%s counts-value=%s",
        tileCount, parsed.value.tileOffsets.type, parsed.value.tileByteCounts.type,
        parsed.value.tileByteCounts.valueOffset);
    auto offsets = new uint[tileCount];
    auto counts = new uint[tileCount];
    auto offsetsResult = readLongArray(tiff[], true,
        parsed.value.tileOffsets.valueOffset, tileCount, offsets[]);
    require(offsetsResult.status == ArrayStatus.ok, "tile offsets");
    if (parsed.value.tileByteCounts.type == 4)
        require(readLongArray(tiff[], true,
            parsed.value.tileByteCounts.valueOffset, tileCount, counts[]).status
            == ArrayStatus.ok, "tile byte counts");
    else if (tileCount == 2)
    {
        counts[0] = parsed.value.tileByteCounts.valueOffset & 0xffff;
        counts[1] = parsed.value.tileByteCounts.valueOffset >> 16;
    }
    else
    {
        auto shortCounts = new ushort[tileCount];
        require(readShortArray(tiff[], true,
            parsed.value.tileByteCounts.valueOffset, tileCount, shortCounts[]).status
            == ArrayStatus.ok, "short tile byte counts");
        foreach (i; 0 .. tileCount)
            counts[i] = shortCounts[i];
    }
    auto tiles = new Block[tileCount];
    foreach (i; 0 .. tileCount)
        tiles[i] = Block(offsets[i], counts[i]);
    ubyte[] output = new ubyte[expected.length];
    ulong observed;
    foreach (iteration; 0 .. iterations)
    {
        auto decoded = decodeTiles(tiff, tiles[], width, height, tileWidth,
            tileHeight, 1, 2, output[], Layout(width * 2, 2, 2));
        require(decoded == DecodeStatus.ok, "tile decode");
        if (iteration == 0 || iteration + 1 == iterations)
            require(output == expected, "GDAL pixel comparison");
        observed = observed * 131 + consume(output[]) + iteration + 1;
    }
    writefln("TIFF tile oracle passed: bytes=%s tiles=%s staging=0 "
        ~ "copied-per-iteration=%s checksum=%s",
        output.length, tileCount, output.length, observed);
}
