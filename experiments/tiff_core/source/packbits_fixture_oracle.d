module packbits_fixture_oracle;

import std.file : read;
import std.stdio : writefln;
import ifd_result : parse, Status;
import tag_arrays : readLongArray, readShortArray, ArrayStatus;
import block_bridge : Block;
import payload_decode : Layout, DecodeStatus;
import compressed_strip_bridge : decodePackBitsStrips;

void main(string[] args)
{
    assert(args.length == 3);
    auto tiff = cast(const(ubyte)[]) read(args[1]);
    auto expected = cast(const(ubyte)[]) read(args[2]);
    auto parsed = parse(tiff);
    assert(parsed.status == Status.ok && parsed.value.compression == 32773);
    assert(parsed.value.stripOffsets.count == parsed.value.stripByteCounts.count);
    auto stripCount = parsed.value.stripOffsets.count;
    auto offsets = new uint[stripCount];
    auto counts = new uint[stripCount];
    if (stripCount == 1)
        offsets[0] = parsed.value.stripOffsets.inlineValue;
    else if (stripCount == 1)
        counts[0] = parsed.value.stripByteCounts.inlineValue;
    else
        assert(readLongArray(tiff[], true, parsed.value.stripOffsets.valueOffset,
            stripCount, offsets[]).status == ArrayStatus.ok);
    if (stripCount == 1)
        counts[0] = parsed.value.stripByteCounts.inlineValue;
    else if (parsed.value.stripByteCounts.type == 4)
        assert(readLongArray(tiff[], true, parsed.value.stripByteCounts.valueOffset,
            stripCount, counts[]).status == ArrayStatus.ok);
    else
    {
        auto shortCounts = new ushort[stripCount];
        assert(readShortArray(tiff[], true, parsed.value.stripByteCounts.valueOffset,
            stripCount, shortCounts[]).status == ArrayStatus.ok);
        if (stripCount == 1 && parsed.value.stripByteCounts.valueOffset <= 0xffff)
            counts[0] = parsed.value.stripByteCounts.valueOffset & 0xffff;
        else foreach (i; 0 .. stripCount) counts[i] = shortCounts[i];
    }
    auto strips = new Block[stripCount];
    foreach (i; 0 .. stripCount) strips[i] = Block(offsets[i], counts[i]);
    ubyte[] output = new ubyte[expected.length];
    ubyte[] scratch = new ubyte[parsed.value.width * parsed.value.rowsPerStrip];
    auto status = decodePackBitsStrips(tiff, strips[], parsed.value.width,
        parsed.value.height, parsed.value.rowsPerStrip, 1, 1, output[],
        scratch[], Layout(parsed.value.width, 1, 1));
    assert(status == DecodeStatus.ok && output == expected);
    writefln("PackBits TIFF oracle passed: bytes=%s strips=%s", output.length, stripCount);
}
