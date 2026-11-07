module packbits;

enum Status { ok, truncated, destinationTooSmall, invalidRun }

struct Result
{
    Status status;
    size_t written;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

Result decode(const(ubyte)[] source, scope ubyte[] destination)
    @safe pure nothrow @nogc
{
    size_t input;
    size_t output;
    while (input < source.length)
    {
        auto control = cast(byte) source[input++];
        if (control >= 0)
        {
            auto count = cast(size_t) control + 1;
            if (count > source.length - input)
                return Result(Status.truncated, output);
            if (count > destination.length - output)
                return Result(Status.destinationTooSmall, output);
            destination[output .. output + count] = source[input .. input + count];
            input += count;
            output += count;
        }
        else if (control != byte.min)
        {
            auto count = cast(size_t) (1 - control);
            if (input >= source.length)
                return Result(Status.truncated, output);
            if (count > destination.length - output)
                return Result(Status.destinationTooSmall, output);
            destination[output .. output + count] = source[input];
            input++;
            output += count;
        }
        // -128 is a no-op marker in PackBits.
    }
    return Result(Status.ok, output);
}

version (PackBitsProbe)
@safe @nogc nothrow
void main()
{
    ubyte[6] encoded = [2, 1, 2, 3, cast(ubyte) 0xfe, 9];
    ubyte[6] output;
    auto result = decode(encoded[], output[]);
    assert(result.ok && result.written == 6 && output == [1, 2, 3, 9, 9, 9]);
    assert(decode(encoded[], output[][0 .. 5]).status == Status.destinationTooSmall);
    ubyte[1] truncated = [4];
    assert(decode(truncated[], output[]).status == Status.truncated);
    ubyte[1] truncatedRun = [cast(ubyte) 0xfe];
    assert(decode(truncatedRun[], output[]).status == Status.truncated);
    ubyte[2] hugeRun = [cast(ubyte) 0xfe, 7];
    assert(decode(hugeRun[], output[]).ok);
}
