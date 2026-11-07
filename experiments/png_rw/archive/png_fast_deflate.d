/// Archived temporary hash-chain Deflate speed/size probe. Compression ownership stays
/// with compression-d; this is not production imageio-d codec code.
module png_fast_deflate;

import compression.checksum : Adler32;

enum hashEntries = 32768;

struct FastResult
{
    bool ok;
    size_t written;
}

private immutable ushort[29] lengthBase =
    [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,
     83,99,115,131,163,195,227,258];
private immutable ubyte[29] lengthExtra =
    [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
private immutable ushort[30] distanceBase =
    [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,
     1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
private immutable ubyte[30] distanceExtra =
    [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

private uint reverse(uint value, uint count) @safe pure nothrow @nogc
{
    uint result;
    foreach (_; 0 .. count) { result = (result << 1) | (value & 1); value >>= 1; }
    return result;
}

private struct Bits
{
    ubyte[] output;
    size_t pos;
    uint pending, count;
    bool put(uint value, uint width) scope @safe pure nothrow @nogc
    {
        pending |= value << count;
        count += width;
        while (count >= 8)
        {
            if (pos >= output.length) return false;
            output[pos++] = cast(ubyte)pending;
            pending >>= 8; count -= 8;
        }
        return true;
    }
    bool finish() scope @safe pure nothrow @nogc
    {
        if (count)
        {
            if (pos >= output.length) return false;
            output[pos++] = cast(ubyte)pending;
        }
        return true;
    }
}

private bool literal(ref Bits bits, uint symbol) @safe pure nothrow @nogc
{
    uint code, width;
    if (symbol <= 143) { code = 0x30 + symbol; width = 8; }
    else if (symbol <= 255) { code = 0x190 + symbol - 144; width = 9; }
    else if (symbol <= 279) { code = symbol - 256; width = 7; }
    else { code = 0xc0 + symbol - 280; width = 8; }
    return bits.put(reverse(code, width), width);
}

private bool match(ref Bits bits, uint length, uint distance)
    @safe pure nothrow @nogc
{
    uint li, di;
    foreach (uint i; 0 .. 29)
        if (length >= lengthBase[i] &&
            length <= lengthBase[i] + ((1U << lengthExtra[i]) - 1))
            li = i;
    foreach (uint i; 0 .. 30)
        if (distance >= distanceBase[i] &&
            distance <= distanceBase[i] + ((1U << distanceExtra[i]) - 1))
            di = i;
    return literal(bits, 257 + li) &&
        bits.put(length - lengthBase[li], lengthExtra[li]) &&
        bits.put(reverse(di, 5), 5) &&
        bits.put(distance - distanceBase[di], distanceExtra[di]);
}

private uint hash3(scope const(ubyte)[] data, size_t p)
    @safe pure nothrow @nogc
{
    return ((cast(uint)data[p] * 251 + data[p + 1]) * 251 + data[p + 2]) &
        (hashEntries - 1);
}

private void insert(scope const(ubyte)[] data, size_t p,
    scope uint[] heads, scope uint[] previous) @safe pure nothrow @nogc
{
    if (data.length - p < 3) return;
    const hash = hash3(data, p);
    previous[p & (hashEntries - 1)] = heads[hash];
    heads[hash] = cast(uint)(p + 1);
}

/// Fixed-Huffman zlib with a 32K hash-chain window and max 32 candidate
/// comparisons per position. Caller owns output and both uint[32768] tables.
FastResult encodeZlibFast(scope const(ubyte)[] input, scope ubyte[] output,
    scope uint[] heads, scope uint[] previous)
    @safe pure nothrow @nogc
{
    if (heads.length < hashEntries || previous.length < hashEntries ||
        input.length >= uint.max || output.length < 8)
        return FastResult(false);
    heads[0 .. hashEntries] = 0;
    previous[0 .. hashEntries] = 0;
    output[0] = 0x78; output[1] = 0x01;
    Bits bits;
    bits.output = output[2 .. $ - 4];
    if (!bits.put(1, 1) || !bits.put(1, 2)) return FastResult(false);
    size_t p;
    while (p < input.length)
    {
        uint bestLength, bestDistance;
        if (input.length - p >= 3)
        {
            uint candidate = heads[hash3(input, p)];
            foreach (_; 0 .. 32)
            {
                if (candidate == 0) break;
                const prior = cast(size_t)candidate - 1;
                if (prior >= p || p - prior > 32768) break;
                const maxLength = input.length - p > 258 ? 258 : input.length - p;
                uint length;
                while (length < maxLength && input[prior + length] == input[p + length])
                    ++length;
                if (length > bestLength && length >= 3)
                { bestLength = length; bestDistance = cast(uint)(p - prior); }
                if (length == maxLength) break;
                candidate = previous[prior & (hashEntries - 1)];
            }
        }
        if (bestLength >= 3)
        {
            if (!match(bits, bestLength, bestDistance)) return FastResult(false);
            foreach (size_t i; p .. p + bestLength) insert(input, i, heads, previous);
            p += bestLength;
        }
        else
        {
            if (!literal(bits, input[p])) return FastResult(false);
            insert(input, p, heads, previous);
            ++p;
        }
    }
    if (!literal(bits, 256) || !bits.finish()) return FastResult(false);
    const footer = 2 + bits.pos;
    Adler32 checksum;
    checksum.update(input);
    const value = checksum.value;
    output[footer] = cast(ubyte)(value >> 24);
    output[footer + 1] = cast(ubyte)(value >> 16);
    output[footer + 2] = cast(ubyte)(value >> 8);
    output[footer + 3] = cast(ubyte)value;
    return FastResult(true, footer + 4);
}
