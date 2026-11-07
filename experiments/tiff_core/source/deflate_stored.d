module deflate_stored;

enum Status { ok, truncated, invalidHeader, unsupportedHuffman, destinationTooSmall }

struct Result
{
    Status status;
    size_t written;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

// Research baseline: RFC 1951 stored blocks only. This deliberately rejects
// fixed/dynamic Huffman blocks until their Pure-D decoder is added; accepting
// only a proven subset is safer than silently delegating to a backend.
Result decode(scope const(ubyte)[] source, scope ubyte[] destination)
    @safe pure nothrow @nogc
{
    size_t input;
    size_t output;
    uint bits;
    uint bitCount;
    while (true)
    {
        while (bitCount < 3)
        {
            if (input >= source.length) return Result(Status.truncated, output);
            bits |= cast(uint) source[input++] << bitCount;
            bitCount += 8;
        }
        auto finalBlock = bits & 1;
        auto blockType = (bits >> 1) & 3;
        bits >>= 3;
        bitCount -= 3;
        if (blockType != 0) return Result(Status.unsupportedHuffman, output);
        bits = 0;
        bitCount = 0;
        if (input + 4 > source.length) return Result(Status.truncated, output);
        auto length = cast(uint) source[input] | (cast(uint) source[input + 1] << 8);
        auto inverse = cast(uint) source[input + 2] | (cast(uint) source[input + 3] << 8);
        input += 4;
        if ((length ^ inverse) != 0xffff) return Result(Status.invalidHeader, output);
        if (length > source.length - input) return Result(Status.truncated, output);
        if (length > destination.length - output) return Result(Status.destinationTooSmall, output);
        destination[output .. output + length] = source[input .. input + length];
        input += length;
        output += length;
        if (finalBlock != 0) return Result(Status.ok, output);
    }
}

version (DeflateStoredProbe)
@safe @nogc nothrow
void main()
{
    ubyte[10] stored = [0x01, 5, 0, cast(ubyte)~5, cast(ubyte)~0,
        'h', 'e', 'l', 'l', 'o'];
    ubyte[5] output;
    assert(decode(stored[], output[]).ok && output == "hello");
    ubyte[4] shortOutput;
    assert(decode(stored[], shortOutput[]).status == Status.destinationTooSmall);
    ubyte[1] fixed = [0x03];
    assert(decode(fixed[], output[]).status == Status.unsupportedHuffman);
}
