module result_parser;

enum ParseStatus
{
    ok,
    truncated,
    invalidByteOrder,
    invalidMagic,
    invalidOffset
}

struct Header
{
    bool littleEndian;
    uint firstIfdOffset;
}

struct ParseResult
{
    ParseStatus status;
    Header value;

    @property bool isOk() const @safe pure nothrow @nogc
    {
        return status == ParseStatus.ok;
    }
}

ParseResult parseHeader(const(ubyte)[] bytes)
    @safe pure nothrow @nogc
{
    if (bytes.length < 8)
        return ParseResult(ParseStatus.truncated, Header.init);

    bool little;
    if (bytes[0] == 'I' && bytes[1] == 'I')
        little = true;
    else if (bytes[0] == 'M' && bytes[1] == 'M')
        little = false;
    else
        return ParseResult(ParseStatus.invalidByteOrder, Header.init);

    ushort magic = little
        ? cast(ushort)(bytes[2] | (bytes[3] << 8))
        : cast(ushort)((bytes[2] << 8) | bytes[3]);
    if (magic != 42)
        return ParseResult(ParseStatus.invalidMagic, Header.init);

    uint offset = little
        ? cast(uint)(bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24))
        : cast(uint)((bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7]);
    if (offset > bytes.length)
        return ParseResult(ParseStatus.invalidOffset, Header.init);

    return ParseResult(ParseStatus.ok, Header(little, offset));
}

@safe @nogc nothrow
void main()
{
    ubyte[8] little = [0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00];
    auto valid = parseHeader(little[]);
    assert(valid.isOk && valid.value.littleEndian);
    assert(valid.value.firstIfdOffset == 8);

    ubyte[8] big = [0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08];
    auto bigResult = parseHeader(big[]);
    assert(bigResult.isOk && !bigResult.value.littleEndian);
    assert(bigResult.value.firstIfdOffset == 8);

    auto shortInput = parseHeader(little[][0 .. 7]);
    assert(shortInput.status == ParseStatus.truncated);

    little[2] = 0;
    auto badMagic = parseHeader(little[]);
    assert(badMagic.status == ParseStatus.invalidMagic);
}
