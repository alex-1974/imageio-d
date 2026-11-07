module deflate_copy;

enum Status { ok, invalidDistance, destinationTooSmall }

Status copyBackReference(scope ubyte[] output, ref size_t written,
    size_t distance, size_t length) @safe pure nothrow @nogc
{
    if (distance == 0 || distance > written)
        return Status.invalidDistance;
    if (length > output.length - written)
        return Status.destinationTooSmall;
    foreach (i; 0 .. length)
        output[written + i] = output[written - distance + i % distance];
    written += length;
    return Status.ok;
}

version (DeflateCopyProbe)
@safe @nogc nothrow
void main()
{
    ubyte[8] output;
    ubyte[3] seed = [1, 2, 3];
    output[0 .. 3] = seed[];
    size_t written = 3;
    assert(copyBackReference(output[], written, 3, 5) == Status.ok);
    ubyte[8] expected = [1, 2, 3, 1, 2, 3, 1, 2];
    assert(written == 8 && output == expected);
    written = 3;
    assert(copyBackReference(output[], written, 0, 1) == Status.invalidDistance);
    assert(copyBackReference(output[], written, 4, 1) == Status.invalidDistance);
    assert(copyBackReference(output[], written, 1, 6) == Status.destinationTooSmall);
}
