module tiff_core;

import std.stdio : writeln;

enum ByteOrder { little, big }

class ParseError : Exception
{
    this(string message) @safe pure nothrow @nogc
    {
        super(message);
    }
}

struct TiffInfo
{
    ByteOrder order;
    ushort width;
    ushort height;
    ushort samplesPerPixel;
    ushort bitsPerSample;
    ushort compression;
    ushort planarConfiguration;
}

struct Cursor
{
    const(ubyte)[] bytes;
    ByteOrder order;

    bool has(size_t offset, size_t count) const @safe pure nothrow @nogc
    {
        return offset <= bytes.length && count <= bytes.length - offset;
    }

    ushort u16(size_t offset) const @safe pure nothrow @nogc
    {
        assert(has(offset, 2));
        if (order == ByteOrder.little)
            return cast(ushort)(bytes[offset] | (bytes[offset + 1] << 8));
        return cast(ushort)((bytes[offset] << 8) | bytes[offset + 1]);
    }

    uint u32(size_t offset) const @safe pure nothrow @nogc
    {
        assert(has(offset, 4));
        if (order == ByteOrder.little)
            return cast(uint)(bytes[offset]
                | (bytes[offset + 1] << 8)
                | (bytes[offset + 2] << 16)
                | (bytes[offset + 3] << 24));
        return cast(uint)((bytes[offset] << 24)
            | (bytes[offset + 1] << 16)
            | (bytes[offset + 2] << 8)
            | bytes[offset + 3]);
    }
}

TiffInfo parse(const(ubyte)[] bytes) @safe pure
{
    if (bytes.length < 8)
        throw new ParseError("truncated TIFF header");

    ByteOrder order;
    if (bytes[0] == 'I' && bytes[1] == 'I')
        order = ByteOrder.little;
    else if (bytes[0] == 'M' && bytes[1] == 'M')
        order = ByteOrder.big;
    else
        throw new ParseError("invalid TIFF byte order");

    auto cursor = Cursor(bytes, order);
    if (cursor.u16(2) != 42)
        throw new ParseError("invalid TIFF magic");

    const ifdOffset = cursor.u32(4);
    if (ifdOffset > size_t.max || !cursor.has(ifdOffset, 2))
        throw new ParseError("IFD offset outside input");

    const count = cursor.u16(ifdOffset);
    const entriesOffset = ifdOffset + 2;
    if (count > (size_t.max - entriesOffset) / 12
        || !cursor.has(entriesOffset, cast(size_t) count * 12 + 4))
        throw new ParseError("truncated IFD");

    TiffInfo info = TiffInfo(order, 0, 0, 1, 1, 1, 1);
    foreach (i; 0 .. count)
    {
        const offset = entriesOffset + cast(size_t) i * 12;
        const tag = cursor.u16(offset);
        const type = cursor.u16(offset + 2);
        const valueCount = cursor.u32(offset + 4);
        if (valueCount != 1)
            continue;
        const valueOffset = offset + 8;
        ushort value;
        if (type == 3)
            value = cursor.u16(valueOffset);
        else if (type == 4)
            value = cast(ushort) cursor.u32(valueOffset);
        else
            continue;

        switch (tag)
        {
            case 256: info.width = value; break;
            case 257: info.height = value; break;
            case 259: info.compression = value; break;
            case 277: info.samplesPerPixel = value; break;
            case 284: info.planarConfiguration = value; break;
            default: break;
        }
    }
    return info;
}

ubyte[] littleFixture() @safe
{
    // II, magic 42, IFD at byte 8, four SHORT/LONG entries.
    return [
        0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00,
        0x04, 0x00,
        0x00, 0x01, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x80, 0x02, 0x00, 0x00,
        0x01, 0x01, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0x00, 0x00,
        0x11, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
        0x15, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ];
}

void expectFailure(const(ubyte)[] bytes) @safe
{
    bool failed;
    try { auto ignored = parse(bytes); } catch (ParseError) { failed = true; }
    assert(failed);
}

@safe void main()
{
    auto info = parse(littleFixture());
    assert(info.order == ByteOrder.little);
    assert(info.width == 640 && info.height == 320);
    assert(info.compression == 1);
    assert(info.samplesPerPixel == 3);

    expectFailure(littleFixture()[0 .. 5]);
    auto invalid = littleFixture();
    invalid[2] = 0;
    expectFailure(invalid);
    invalid = littleFixture();
    invalid[4] = 0xff;
    invalid[5] = 0xff;
    expectFailure(invalid);

    writeln("tiff core probe passed");
}
