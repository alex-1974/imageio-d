module fixture_negative;

import std.file : read;
import ifd_result : parse, Status;
import tag_arrays : readLongArray, ArrayStatus;

private ushort u16(const(ubyte)[] bytes, size_t at, bool little)
{
    return little ? cast(ushort)(bytes[at] | bytes[at + 1] << 8)
        : cast(ushort)(bytes[at] << 8 | bytes[at + 1]);
}

private uint u32(const(ubyte)[] bytes, size_t at, bool little)
{
    return little
        ? cast(uint)(bytes[at] | bytes[at + 1] << 8
            | bytes[at + 2] << 16 | bytes[at + 3] << 24)
        : cast(uint)(bytes[at] << 24 | bytes[at + 1] << 16
            | bytes[at + 2] << 8 | bytes[at + 3]);
}

private void put32(ubyte[] bytes, size_t at, uint value, bool little)
{
    foreach (i; 0 .. 4)
        bytes[at + i] = cast(ubyte)(value >> (little ? i * 8 : (3 - i) * 8));
}

private size_t entry(const(ubyte)[] bytes, ushort wanted, bool little)
{
    const ifd = u32(bytes, 4, little);
    const count = u16(bytes, ifd, little);
    foreach (i; 0 .. count)
    {
        const at = cast(size_t) ifd + 2 + i * 12;
        if (u16(bytes, at, little) == wanted) return at;
    }
    return size_t.max;
}

private void check(const(ubyte)[] original)
{
    assert(parse(original).status == Status.ok);
    const little = original[0] == 'I';

    auto truncated = original[0 .. 7];
    assert(parse(truncated).status == Status.truncated);

    auto badOrder = original.dup;
    badOrder[0] = 'X';
    assert(parse(badOrder).status == Status.invalidOrder);

    auto badMagic = original.dup;
    badMagic[2] = 0;
    assert(parse(badMagic).status == Status.invalidMagic);

    auto badIfd = original.dup;
    badIfd[4] = 0xff;
    badIfd[5] = 0xff;
    badIfd[6] = 0xff;
    badIfd[7] = 0x7f;
    assert(parse(badIfd).status == Status.invalidOffset);

    auto excessiveEntries = original.dup;
    const ifd = u32(original, 4, little);
    excessiveEntries[ifd] = 0xff;
    excessiveEntries[ifd + 1] = 0xff;
    assert(parse(excessiveEntries).status == Status.truncated);

    auto offsetsEntry = entry(original, 273, little);
    auto countsEntry = entry(original, 279, little);
    if (offsetsEntry == size_t.max)
    {
        offsetsEntry = entry(original, 324, little);
        countsEntry = entry(original, 325, little);
    }
    assert(offsetsEntry != size_t.max && countsEntry != size_t.max);

    auto zeroCount = original.dup;
    put32(zeroCount, offsetsEntry + 4, 0, little);
    assert(parse(zeroCount).status == Status.invalidOffset);

    auto mismatchedCount = original.dup;
    put32(mismatchedCount, offsetsEntry + 4,
        u32(original, countsEntry + 4, little) + 1, little);
    assert(parse(mismatchedCount).status == Status.invalidOffset);

    // Multi-strip fixtures use an external LONG offset array. Parsing keeps
    // that value borrowed; the explicit array read must reject an invalid
    // range without touching caller-owned output.
    if (u32(original, offsetsEntry + 4, little) > 1)
    {
        auto externalRange = original.dup;
        put32(externalRange, offsetsEntry + 8,
            cast(uint)(original.length + 1), little);
        const parsed = parse(externalRange);
        assert(parsed.status == Status.ok);
        const values = parsed.value.stripOffsets.count != 0
            ? parsed.value.stripOffsets : parsed.value.tileOffsets;
        auto output = new uint[values.count];
        assert(readLongArray(externalRange, little,
            values.valueOffset, values.count, output[]).status ==
            ArrayStatus.truncated);
    }
}

void main(string[] args)
{
    assert(args.length >= 2);
    foreach (path; args[1 .. $])
        check(cast(const(ubyte)[]) read(path));
}
