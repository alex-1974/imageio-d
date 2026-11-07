module packbits_tile_oracle;

import std.file : read;
import std.stdio : writefln;
import ifd_result : parse, Status;
import tag_arrays : readLongArray, ArrayStatus;
import block_bridge : Block;
import compressed_tile_bridge : decodePackBitsTiles;
import payload_decode : Layout, DecodeStatus;

void main(string[] args)
{
    assert(args.length == 3);
    auto tiff = cast(const(ubyte)[]) read(args[1]);
    auto expected = cast(const(ubyte)[]) read(args[2]);
    auto parsed = parse(tiff);
    assert(parsed.status == Status.ok && parsed.value.compression == 32773);
    auto count = parsed.value.tileOffsets.count;
    auto offsets = new uint[count];
    auto counts = new uint[count];
    if (count == 1)
    {
        offsets[0] = parsed.value.tileOffsets.inlineValue;
        counts[0] = parsed.value.tileByteCounts.inlineValue;
    }
    else
    {
        assert(readLongArray(tiff[], true, parsed.value.tileOffsets.valueOffset, count,
            offsets[]).status == ArrayStatus.ok);
        assert(readLongArray(tiff[], true, parsed.value.tileByteCounts.valueOffset, count,
            counts[]).status == ArrayStatus.ok);
    }
    auto tiles = new Block[count];
    foreach (i; 0 .. count) tiles[i] = Block(offsets[i], counts[i]);
    ubyte[] output = new ubyte[expected.length];
    ubyte[512] scratch;
    auto status = decodePackBitsTiles(tiff, tiles[], 12, 7, 16, 16, 1, 1,
        output[], scratch[], Layout(12, 1, 1));
    assert(status == DecodeStatus.ok && output == expected);
    writefln("PackBits tile oracle passed: bytes=%s tiles=%s", output.length, count);
}
