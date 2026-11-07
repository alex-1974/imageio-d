module tiff_planar_oracle;

import std.file : read;
import std.stdio : writefln;
import std.conv : to;
import ifd_result : parse, Status;
import tag_arrays : readLongArray, readShortArray, ArrayStatus;
import block_bridge : Block, decodePlanarStrips;
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
    require(args.length == 5 || args.length == 6, "arguments");
    auto tiff = cast(const(ubyte)[]) read(args[1]);
    auto expected = cast(const(ubyte)[]) read(args[2]);
    auto width = to!uint(args[3]);
    auto height = to!uint(args[4]);
    auto iterations = args.length == 6 ? to!uint(args[5]) : 1;
    auto parsed = parse(tiff);
    require(parsed.status == Status.ok, "TIFF parse");
    require(parsed.value.samplesPerPixel == 3, "sample count");
    require(parsed.value.planarConfiguration == 2, "planar layout");
    require(parsed.value.rowsPerStrip != 0, "rows per strip");
    require(parsed.value.stripOffsets.count == parsed.value.stripByteCounts.count,
        "strip table lengths");
    auto stripCount = parsed.value.stripOffsets.count;
    require(stripCount % 3 == 0, "strip count");
    auto offsets = new uint[stripCount];
    auto counts = new uint[stripCount];
    require(readLongArray(tiff[], true, parsed.value.stripOffsets.valueOffset,
        stripCount, offsets[]).status == ArrayStatus.ok, "strip offsets");
    if (parsed.value.stripByteCounts.type == 4)
        require(readLongArray(tiff[], true, parsed.value.stripByteCounts.valueOffset,
            stripCount, counts[]).status == ArrayStatus.ok, "strip byte counts");
    else
    {
        auto shortCounts = new ushort[stripCount];
        require(readShortArray(tiff[], true, parsed.value.stripByteCounts.valueOffset,
            stripCount, shortCounts[]).status == ArrayStatus.ok,
            "short strip byte counts");
        foreach (i; 0 .. stripCount)
            counts[i] = shortCounts[i];
    }

    auto strips = new Block[stripCount];
    size_t payloadBytes;
    foreach (i; 0 .. stripCount)
    {
        require(offsets[i] <= tiff.length && counts[i] <= tiff.length - offsets[i],
            "strip range");
        strips[i] = Block(offsets[i], counts[i]);
        payloadBytes += counts[i];
    }
    ubyte[] output = new ubyte[expected.length];
    ulong observed;
    foreach (iteration; 0 .. iterations)
    {
        auto decoded = decodePlanarStrips(tiff, strips[], width, height,
            parsed.value.rowsPerStrip, 3, 1, output[], Layout(width * 3, 3, 1));
        require(decoded == DecodeStatus.ok, "planar strip decode");
        if (iteration == 0 || iteration + 1 == iterations)
            require(output == expected, "GDAL pixel comparison");
        observed = observed * 131 + consume(output[]) + iteration + 1;
    }
    writefln("TIFF planar oracle passed: bytes=%s strips=%s payload=%s "
        ~ "staging=0 copied-per-iteration=%s checksum=%s",
        output.length, stripCount, payloadBytes, output.length, observed);
}
