module deflate_huffman;

enum Status { ok, invalidTable, truncated, noSymbol }

struct BitReader
{
    const(ubyte)[] source;
    size_t input;
    uint bits;
    uint available;
    Status status;

    uint read(uint amount) @safe pure nothrow @nogc
    {
        while (available < amount)
        {
            if (input >= source.length) { status = Status.truncated; return 0; }
            bits |= cast(uint) source[input++] << available;
            available += 8;
        }
        auto value = bits & ((1U << amount) - 1);
        bits >>= amount;
        available -= amount;
        status = Status.ok;
        return value;
    }
}

struct Table
{
    ushort[16] count;
    ushort[16] firstCode;
    ushort[16] firstSymbol;
    ushort[288] symbols;
    ushort symbolCount;

    Status build(scope const(ubyte)[] lengths) @safe pure nothrow @nogc
    {
        count[] = 0;
        symbolCount = 0;
        foreach (length; lengths)
        {
            if (length > 15) return Status.invalidTable;
            if (length != 0) count[length]++;
        }
        uint code;
        foreach (bits; 1 .. 16)
        {
            code = (code + count[bits - 1]) << 1;
            firstCode[bits] = cast(ushort) code;
            firstSymbol[bits] = cast(ushort)(bits == 1 ? 0 : firstSymbol[bits - 1] + count[bits - 1]);
        }
        foreach (symbol, length; lengths)
        {
            if (length == 0) continue;
            if (symbolCount >= symbols.length) return Status.invalidTable;
            symbols[firstSymbol[length]++] = cast(ushort) symbol;
            symbolCount++;
        }
        foreach (bits; 1 .. 16)
            firstSymbol[bits] = cast(ushort)(bits == 1 ? 0 : firstSymbol[bits - 1] + count[bits - 1]);
        return Status.ok;
    }

    Status decode(ref BitReader reader, out ushort symbol)
        @safe pure nothrow @nogc
    {
        uint code;
        foreach (bits; 1 .. 16)
        {
            code |= reader.read(1) << (bits - 1);
            if (reader.status != Status.ok) return reader.status;
            auto normal = reverseBits(code, bits);
            if (normal >= firstCode[bits] && normal - firstCode[bits] < count[bits])
            {
                symbol = symbols[firstSymbol[bits] + normal - firstCode[bits]];
                return Status.ok;
            }
        }
        return Status.noSymbol;
    }
}

private uint reverseBits(uint value, uint count) @safe pure nothrow @nogc
{
    uint result;
    foreach (_; 0 .. count) { result = (result << 1) | (value & 1); value >>= 1; }
    return result;
}

version (DeflateHuffmanProbe)
@safe @nogc nothrow
void main()
{
    ubyte[3] lengths = [1, 2, 2];
    Table table;
    assert(table.build(lengths[]) == Status.ok);
    ubyte[1] encoded = [0x1a]; // 0, 10, 11 in the deflate bit order
    BitReader reader = BitReader(encoded[]);
    ushort symbol;
    assert(table.decode(reader, symbol) == Status.ok && symbol == 0);
    assert(table.decode(reader, symbol) == Status.ok && symbol == 1);
    assert(table.decode(reader, symbol) == Status.ok && symbol == 2);
}
