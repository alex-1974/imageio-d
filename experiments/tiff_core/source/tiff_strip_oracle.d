module tiff_strip_oracle;

import std.file : read;
import std.stdio : writefln;
import std.conv : to;
import ifd_result : parse, Status, TagValue;
import block_bridge : Block, decodeStrips;
import payload_decode : DecodeStatus;
import payload_decode : Layout;

uint scalar(TagValue value) @safe pure nothrow @nogc
{
    // Research fixture path: count-one LONG values are inline in the IFD.
    return value.inlineValue;
}

void main(string[] args)
{
    assert(args.length == 3 || args.length == 4);
    auto tiff = cast(const(ubyte)[]) read(args[1]);
    auto expected = cast(const(ubyte)[]) read(args[2]);
    auto sampleBytes = args.length > 3 ? to!uint(args[3]) : 1;
    auto parsed = parse(tiff);
    assert(parsed.status == Status.ok);
    assert(parsed.value.samplesPerPixel == 1 || parsed.value.samplesPerPixel == 3);
    assert(parsed.value.stripOffsets.count == parsed.value.stripByteCounts.count);
    assert(parsed.value.stripOffsets.count == 1);

    Block[1] blocks;
    blocks[0] = Block(scalar(parsed.value.stripOffsets),
        scalar(parsed.value.stripByteCounts));
    ubyte[] output = new ubyte[expected.length];
    auto bands = parsed.value.samplesPerPixel;
    auto decoded = decodeStrips(tiff, blocks[], parsed.value.width,
        parsed.value.height, parsed.value.height, bands, sampleBytes, output[],
        Layout(parsed.value.width * bands * sampleBytes, bands * sampleBytes,
            sampleBytes));
    if (decoded != DecodeStatus.ok)
        writefln("strip decode failed code=%s offset=%s count=%s width=%s height=%s expected=%s",
            decoded, blocks[0].offset, blocks[0].byteCount,
            parsed.value.width, parsed.value.height, expected.length);
    assert(decoded == DecodeStatus.ok);
    assert(output == expected);
    writefln("TIFF strip oracle passed: bytes=%s staging=0 "
        ~ "copied-per-iteration=%s", output.length, output.length);
}
