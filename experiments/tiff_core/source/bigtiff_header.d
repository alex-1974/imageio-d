module bigtiff_header;

enum Status { ok, truncated, invalidOrder, invalidMagic, unsupportedOffsetSize,
    invalidOffset, overflow, invalidType, invalidIndex, directoryLimit, cyclicDirectory }

struct Result
{
    Status status;
    ulong firstIfd;
}

struct Entry
{
    ushort tag, type;
    ulong count, value;
    ulong slot;
}

struct Directory
{
    Status status;
    bool little;
    ulong offset, entries, count, next;
}

/// A caller-owned byte window at an absolute file offset.
struct RangeWindow
{
    ulong offset;
    const(ubyte)[] bytes;

    bool contains(ulong start, ulong length) const scope @safe pure nothrow @nogc
    {
        return start >= offset && start - offset <= bytes.length &&
            length <= bytes.length - (start - offset);
    }
}

private bool has(const(ubyte)[] bytes, ulong offset, ulong length)
    @safe pure nothrow @nogc
{
    return offset <= bytes.length && length <= bytes.length - offset;
}

uint read32(const(ubyte)[] bytes, size_t p, bool little)
    @safe pure nothrow @nogc
{
    uint v;
    foreach (i; 0 .. 4)
        v |= cast(uint)bytes[p + i] << (8 * (little ? i : 3 - i));
    return v;
}

private uint typeSize(ushort type) @safe pure nothrow @nogc
{
    switch (type)
    {
        case 1: case 2: case 6: case 7: return 1;
        case 3: case 8: return 2;
        case 4: case 9: case 11: case 13: return 4;
        case 5: case 10: case 12: case 16: case 17: case 18: return 8;
        default: return 0;
    }
}

Directory directoryAt(const(ubyte)[] bytes, ulong off, bool little)
    @safe pure nothrow @nogc
{
    if (!has(bytes, off, 8)) return Directory(Status.invalidOffset);
    auto count = read64(bytes, cast(size_t)off, little);
    if (count > (ulong.max - 16) / 20) return Directory(Status.overflow);
    auto size = count * 20 + 16;
    if (!has(bytes, off, size)) return Directory(Status.invalidOffset);
    auto entries = off + 8;
    auto next = read64(bytes, cast(size_t)(entries + count * 20), little);
    if (next != 0 && !has(bytes, next, 8)) return Directory(Status.invalidOffset);
    return Directory(Status.ok, little, off, entries, count, next);
}

Directory parseDirectory(const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    auto header = parse(bytes);
    if (header.status != Status.ok) return Directory(header.status);
    return directoryAt(bytes, header.firstIfd, bytes[0] == 'I');
}

/// Parse an IFD supplied as a range window at the absolute header offset.
/// Entry slots are relative to `window`; external values need a separate range.
Directory parseDirectoryWindow(const(ubyte)[] headerBytes,
    const(ubyte)[] window, ulong absoluteOffset) @safe pure nothrow @nogc
{
    auto header = parse(headerBytes);
    if (header.status != Status.ok) return Directory(header.status);
    if (header.firstIfd != absoluteOffset) return Directory(Status.invalidOffset);
    if (window.length < 16) return Directory(Status.truncated);
    bool little = headerBytes[0] == 'I';
    auto count = read64(window, 0, little);
    if (count > (ulong.max - 16) / 20) return Directory(Status.overflow);
    auto size = count * 20 + 16;
    if (!has(window, 0, size)) return Directory(Status.truncated);
    return Directory(Status.ok, little, absoluteOffset, 8, count,
        read64(window, cast(size_t)(8 + count * 20), little));
}

/// Bounds the number of directories and detects cycles without allocation.
Status walkDirectories(const(ubyte)[] bytes, ulong maxDirectories,
    out ulong visited) @safe pure nothrow @nogc
{
    visited = 0;
    auto header = parse(bytes);
    if (header.status != Status.ok) return header.status;
    auto little = bytes[0] == 'I';
    auto slow = header.firstIfd;
    auto fast = slow;
    while (slow != 0)
    {
        if (visited == maxDirectories) return Status.directoryLimit;
        auto dir = directoryAt(bytes, slow, little);
        if (dir.status != Status.ok) return dir.status;
        ++visited;
        slow = dir.next;
        foreach (_; 0 .. 2)
        {
            if (fast == 0) break;
            auto next = directoryAt(bytes, fast, little);
            if (next.status != Status.ok) return next.status;
            fast = next.next;
        }
        if (slow != 0 && slow == fast) return Status.cyclicDirectory;
    }
    return Status.ok;
}

Status entryAt(const(ubyte)[] bytes, Directory dir, ulong index, out Entry entry)
    @safe pure nothrow @nogc
{
    auto status = entryAtWindow(bytes, dir, index, entry);
    if (status != Status.ok) return status;
    auto length = entry.count * typeSize(entry.type);
    if (length > 8 && !has(bytes, entry.value, length)) return Status.invalidOffset;
    return Status.ok;
}

Status entryAtWindow(const(ubyte)[] bytes, Directory dir, ulong index, out Entry entry)
    @safe pure nothrow @nogc
{
    entry = Entry.init;
    if (dir.status != Status.ok) return dir.status;
    if (index >= dir.count) return Status.invalidIndex;
    auto p = dir.entries + index * 20;
    if (!has(bytes, p, 20)) return Status.invalidOffset;
    entry = Entry(read16(bytes, cast(size_t)p, dir.little),
        read16(bytes, cast(size_t)p + 2, dir.little),
        read64(bytes, cast(size_t)p + 4, dir.little),
        read64(bytes, cast(size_t)p + 12, dir.little), p + 12);
    auto width = typeSize(entry.type);
    if (!width) return Status.invalidType;
    if (entry.count > ulong.max / width) return Status.overflow;
    return Status.ok;
}

Status unsignedAtRange(RangeWindow directoryWindow, Directory dir, Entry entry,
    RangeWindow externalWindow, ulong index, out ulong value)
    @safe pure nothrow @nogc
{
    value = 0;
    if (entry.type != 3 && entry.type != 4 && entry.type != 16 && entry.type != 18)
        return Status.invalidType;
    if (index >= entry.count) return Status.invalidIndex;
    auto width = typeSize(entry.type);
    if (entry.count > ulong.max / width) return Status.overflow;
    auto inlineValue = entry.count * width <= 8;
    if (inlineValue && entry.slot > ulong.max - directoryWindow.offset)
        return Status.overflow;
    auto start = inlineValue ? directoryWindow.offset + entry.slot : entry.value;
    if (index > (ulong.max - start) / width) return Status.overflow;
    start += index * width;
    auto window = inlineValue ? directoryWindow : externalWindow;
    if (!window.contains(start, width)) return Status.invalidOffset;
    auto p = cast(size_t)(start - window.offset);
    value = width == 2 ? read16(window.bytes, p, dir.little) :
        width == 4 ? read32(window.bytes, p, dir.little) :
        read64(window.bytes, p, dir.little);
    return Status.ok;
}

Status unsignedAt(const(ubyte)[] bytes, Directory dir, Entry entry,
    ulong index, out ulong value) @safe pure nothrow @nogc
{
    value = 0;
    if (entry.type != 3 && entry.type != 4 && entry.type != 16 && entry.type != 18)
        return Status.invalidType;
    if (index >= entry.count) return Status.invalidIndex;
    auto width = typeSize(entry.type);
    if (entry.count > ulong.max / width) return Status.overflow;
    auto total = entry.count * width;
    auto start = total <= 8 ? entry.slot : entry.value;
    if (index > (ulong.max - start) / width)
        return Status.overflow;
    auto offset = start + index * width;
    if (!has(bytes, offset, width)) return Status.invalidOffset;
    auto p = cast(size_t)offset;
    value = width == 2 ? read16(bytes, p, dir.little) :
        width == 4 ? read32(bytes, p, dir.little) : read64(bytes, p, dir.little);
    return Status.ok;
}

ushort read16(const(ubyte)[] bytes, size_t p, bool little)
    @safe pure nothrow @nogc
{
    return little ? cast(ushort)(bytes[p] | bytes[p + 1] << 8)
        : cast(ushort)(bytes[p] << 8 | bytes[p + 1]);
}

ulong read64(const(ubyte)[] bytes, size_t p, bool little)
    @safe pure nothrow @nogc
{
    ulong value;
    if (little)
        foreach (i; 0 .. 8) value |= cast(ulong) bytes[p + i] << (i * 8);
    else
        foreach (i; 0 .. 8) value |= cast(ulong) bytes[p + i] << ((7 - i) * 8);
    return value;
}

Result parse(const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    if (bytes.length < 16) return Result(Status.truncated);
    bool little;
    if (bytes[0] == 'I' && bytes[1] == 'I') little = true;
    else if (bytes[0] == 'M' && bytes[1] == 'M') little = false;
    else return Result(Status.invalidOrder);
    if (read16(bytes, 2, little) != 43) return Result(Status.invalidMagic);
    if (read16(bytes, 4, little) != 8 || read16(bytes, 6, little) != 0)
        return Result(Status.unsupportedOffsetSize);
    return Result(Status.ok, read64(bytes, 8, little));
}

version (BigTiffProbe)
@safe @nogc nothrow
void main()
{
    ubyte[16] little = ['I', 'I', 43, 0, 8, 0, 0, 0,
        0x20, 0, 0, 0, 0, 0, 0, 0];
    assert(parse(little[]).status == Status.ok);
    assert(parse(little[]).firstIfd == 0x20);
    assert(parse(little[][0 .. 15]).status == Status.truncated);
    assert(parseDirectory(little[]).status == Status.invalidOffset);
    ubyte[52] directory;
    directory[0 .. 16] = little[];
    directory[32] = 1; // one 20-byte entry plus 8-byte count and next pointer
    directory[40] = 0; directory[41] = 1; // ImageWidth (256)
    directory[42] = 16; // LONG8
    directory[44] = 1; // one value
    assert(parseDirectory(directory[]).status == Status.invalidOffset);
    ubyte[68] complete;
    complete[0 .. 16] = little[];
    complete[32] = 1;
    complete[40] = 0; complete[41] = 1;
    complete[42] = 16;
    complete[44] = 1;
    complete[52] = 42;
    auto parsed = parseDirectory(complete[]);
    assert(parsed.status == Status.ok && parsed.count == 1);
    Entry e;
    assert(entryAt(complete[], parsed, 0, e) == Status.ok);
    ulong v;
    assert(unsignedAt(complete[], parsed, e, 0, v) == Status.ok && v == 42);
    assert(unsignedAt(complete[], parsed, e, 1, v) == Status.invalidIndex);
    ubyte[36] rangeIfd = complete[32 .. 68];
    auto ranged = parseDirectoryWindow(little[], rangeIfd[], 32);
    assert(ranged.status == Status.ok);
    assert(entryAtWindow(rangeIfd[], ranged, 0, e) == Status.ok);
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow.init, 0, v) == Status.ok && v == 42);
    rangeIfd[12] = 2; // two LONG8 values, stored outside the IFD
    rangeIfd[20] = 0; rangeIfd[21] = 1;
    rangeIfd[24] = 1; // offset 0x1_0000_0100
    assert(entryAtWindow(rangeIfd[], ranged, 0, e) == Status.ok);
    ubyte[16] external;
    external[0] = 7;
    external[8] = 9;
    auto externalOffset = 0x1_0000_0100UL;
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow(externalOffset, external[]), 0, v) == Status.ok && v == 7);
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow(externalOffset, external[]), 1, v) == Status.ok && v == 9);
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow(externalOffset, external[][0 .. 15]), 1, v) == Status.invalidOffset);
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow(externalOffset + 1, external[]), 0, v) == Status.invalidOffset);
    assert(unsignedAtRange(RangeWindow(32, rangeIfd[]), ranged, e,
        RangeWindow(externalOffset, external[]), 2, v) == Status.invalidIndex);
    complete[60] = 0xff; // invalid next IFD
    assert(parseDirectory(complete[]).status == Status.invalidOffset);
    complete[60] = 0;
    complete[52] = 0xff; complete[53] = 0xff;
    complete[54] = 0xff; complete[55] = 0xff;
    complete[56] = 0xff; complete[57] = 0xff;
    complete[58] = 0xff; complete[59] = 0xff;
    assert(entryAt(complete[], parsed, 0, e) == Status.ok);
    assert(unsignedAt(complete[], parsed, e, 0, v) == Status.ok && v == ulong.max);
    complete[44] = 0xff; complete[45] = 0xff; complete[46] = 0xff;
    complete[47] = 0xff; complete[48] = 0xff; complete[49] = 0xff;
    complete[50] = 0xff; complete[51] = 0xff;
    assert(entryAt(complete[], parsed, 0, e) == Status.overflow);
    complete[44] = 1;
    complete[45] = 0; complete[46] = 0; complete[47] = 0;
    complete[48] = 0; complete[49] = 0; complete[50] = 0; complete[51] = 0;
    ulong visited;
    assert(walkDirectories(complete[], 1, visited) == Status.ok && visited == 1);
    complete[60] = 32;
    assert(walkDirectories(complete[], 4, visited) == Status.cyclicDirectory);
    complete[60] = 64; // second empty directory starts at 64, needs 16 bytes
    ubyte[80] chain;
    chain[0 .. complete.length] = complete[];
    assert(walkDirectories(chain[], 1, visited) == Status.directoryLimit);
    assert(walkDirectories(chain[], 2, visited) == Status.ok && visited == 2);
}
