module deflate_tables;

struct Range
{
    ushort base;
    ubyte extra;
}

enum Range[29] lengthRanges = [
    Range(3, 0), Range(4, 0), Range(5, 0), Range(6, 0),
    Range(7, 0), Range(8, 0), Range(9, 0), Range(10, 0),
    Range(11, 1), Range(13, 1), Range(15, 1), Range(17, 1),
    Range(19, 2), Range(23, 2), Range(27, 2), Range(31, 2),
    Range(35, 3), Range(43, 3), Range(51, 3), Range(59, 3),
    Range(67, 4), Range(83, 4), Range(99, 4), Range(115, 4),
    Range(131, 5), Range(163, 5), Range(195, 5), Range(227, 5),
    Range(258, 0)
];

enum Range[30] distanceRanges = [
    Range(1, 0), Range(2, 0), Range(3, 0), Range(4, 0),
    Range(5, 1), Range(7, 1), Range(9, 2), Range(13, 2),
    Range(17, 3), Range(25, 3), Range(33, 4), Range(49, 4),
    Range(65, 5), Range(97, 5), Range(129, 6), Range(193, 6),
    Range(257, 7), Range(385, 7), Range(513, 8), Range(769, 8),
    Range(1025, 9), Range(1537, 9), Range(2049, 10), Range(3073, 10),
    Range(4097, 11), Range(6145, 11), Range(8193, 12), Range(12289, 12),
    Range(16385, 13), Range(24577, 13)
];

ubyte fixedLiteralLength(ushort symbol) @safe pure nothrow @nogc
{
    if (symbol <= 143) return 8;
    if (symbol <= 255) return 9;
    if (symbol <= 279) return 7;
    if (symbol <= 287) return 8;
    return 0;
}

ubyte fixedDistanceLength() @safe pure nothrow @nogc { return 5; }

version (DeflateTableProbe)
@safe @nogc nothrow
void main()
{
    assert(lengthRanges[0].base == 3 && lengthRanges[28].base == 258);
    assert(distanceRanges[0].base == 1 && distanceRanges[29].extra == 13);
    assert(fixedLiteralLength(0) == 8);
    assert(fixedLiteralLength(144) == 9);
    assert(fixedLiteralLength(256) == 7);
    assert(fixedLiteralLength(280) == 8);
    assert(fixedDistanceLength() == 5);
}
