module tag_arrays;

enum ArrayStatus { ok, truncated, unsupportedType, overflow, destinationTooSmall }

struct ArrayResult
{
    ArrayStatus status;
    size_t written;
    @property bool ok() const @safe pure nothrow @nogc
    { return status == ArrayStatus.ok; }
}

struct Reader
{
    const(ubyte)[] bytes;
    bool little;

    bool has(size_t p, size_t n) const @safe pure nothrow @nogc
    { return p <= bytes.length && n <= bytes.length - p; }

    uint u32(size_t p) const @safe pure nothrow @nogc
    {
        return little ? cast(uint)(bytes[p] | bytes[p + 1] << 8 | bytes[p + 2] << 16 | bytes[p + 3] << 24)
            : cast(uint)(bytes[p] << 24 | bytes[p + 1] << 16 | bytes[p + 2] << 8 | bytes[p + 3]);
    }

    ushort u16(size_t p) const @safe pure nothrow @nogc
    {
        return little ? cast(ushort)(bytes[p] | bytes[p + 1] << 8)
            : cast(ushort)(bytes[p] << 8 | bytes[p + 1]);
    }
}

// Reads an external SHORT array, such as multi-band BitsPerSample, into
// caller-owned output. Inline values are handled by the IFD layer.
ArrayResult readShortArray(
    const(ubyte)[] bytes,
    bool little,
    uint offset,
    uint count,
    scope ushort[] destination
) @safe pure nothrow @nogc
{
    if (count > destination.length)
        return ArrayResult(ArrayStatus.destinationTooSmall, 0);
    auto reader = Reader(bytes, little);
    if (count > size_t.max / 2)
        return ArrayResult(ArrayStatus.overflow, 0);
    auto byteCount = cast(size_t) count * 2;
    if (!reader.has(offset, byteCount))
        return ArrayResult(ArrayStatus.truncated, 0);
    foreach (i; 0 .. count)
        destination[i] = reader.u16(cast(size_t) offset + i * 2);
    return ArrayResult(ArrayStatus.ok, count);
}

// Reads a LONG array from an external TIFF value area into caller-owned output.
ArrayResult readLongArray(
    const(ubyte)[] bytes,
    bool little,
    uint offset,
    uint count,
    scope uint[] destination
) @safe pure nothrow @nogc
{
    if (count > destination.length)
        return ArrayResult(ArrayStatus.destinationTooSmall, 0);
    auto reader = Reader(bytes, little);
    if (count > size_t.max / 4)
        return ArrayResult(ArrayStatus.overflow, 0);
    auto byteCount = cast(size_t) count * 4;
    if (!reader.has(offset, byteCount))
        return ArrayResult(ArrayStatus.truncated, 0);
    foreach (i; 0 .. count)
        destination[i] = reader.u32(cast(size_t) offset + i * 4);
    return ArrayResult(ArrayStatus.ok, count);
}

version (TagArrayProbe)
@safe @nogc nothrow
void main()
{
    ubyte[8] values = [1, 0, 0, 0, 2, 0, 0, 0];
    uint[2] output;
    auto result = readLongArray(values[], true, 0, 2, output[]);
    assert(result.ok && result.written == 2);
    assert(output == [1, 2]);

    auto tooSmall = readLongArray(values[], true, 0, 2, output[][0 .. 1]);
    assert(tooSmall.status == ArrayStatus.destinationTooSmall);
    auto truncated = readLongArray(values[], true, 4, 2, output[]);
    assert(truncated.status == ArrayStatus.truncated);

    ubyte[6] shortValues = [8, 0, 16, 0, 32, 0];
    ushort[3] shorts;
    auto shortResult = readShortArray(shortValues[], true, 0, 3, shorts[]);
    assert(shortResult.ok && shorts == [8, 16, 32]);
    auto shortTooSmall = readShortArray(shortValues[], true, 0, 3, shorts[][0 .. 2]);
    assert(shortTooSmall.status == ArrayStatus.destinationTooSmall);

    ubyte[4] bigEndianShorts = [0, 8, 0, 16];
    ushort[2] bigEndianOutput;
    auto bigEndianResult = readShortArray(bigEndianShorts[], false, 0, 2, bigEndianOutput[]);
    assert(bigEndianResult.ok && bigEndianOutput == [8, 16]);
    auto shortTruncated = readShortArray(bigEndianShorts[], false, 2, 2, bigEndianOutput[]);
    assert(shortTruncated.status == ArrayStatus.truncated);
}
