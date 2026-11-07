module deflate_fixed;

import deflate_huffman : Status, Table;

struct FixedTables
{
    Table literalLength;
    Table distance;

    Status build() @safe pure nothrow @nogc
    {
        ubyte[288] literalLengths;
        foreach (i; 0 .. 288)
        {
            literalLengths[i] = i <= 143 ? 8 : i <= 255 ? 9 : i <= 279 ? 7 : 8;
        }
        ubyte[32] distanceLengths;
        distanceLengths[] = 5;
        auto result = literalLength.build(literalLengths[]);
        if (result != Status.ok) return result;
        return distance.build(distanceLengths[]);
    }
}

enum SymbolKind { literal, endOfBlock, length }

SymbolKind classify(ushort symbol) @safe pure nothrow @nogc
{
    if (symbol < 256) return SymbolKind.literal;
    if (symbol == 256) return SymbolKind.endOfBlock;
    return SymbolKind.length;
}

version (DeflateFixedProbe)
@safe @nogc nothrow
void main()
{
    FixedTables tables;
    assert(tables.build() == Status.ok);
    assert(classify(65) == SymbolKind.literal);
    assert(classify(256) == SymbolKind.endOfBlock);
    assert(classify(257) == SymbolKind.length);
}
