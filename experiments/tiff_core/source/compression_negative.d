module compression_negative;

import packbits : decode, Status;

@safe @nogc nothrow
void main()
{
    ubyte[1] literalControl = [10];
    ubyte[4] small;
    assert(decode(literalControl[], small[]).status == Status.truncated);

    ubyte[2] repeatControl = [cast(ubyte) 0xfe, 7];
    ubyte[1] tooSmall;
    assert(decode(repeatControl[], tooSmall[]).status == Status.destinationTooSmall);

    // A legal run may expand only into the caller-owned destination. The
    // decoder never allocates an unbounded expansion buffer.
    ubyte[2] boundedRun = [cast(ubyte) 0xfe, 9];
    ubyte[3] bounded;
    assert(decode(boundedRun[], bounded[]).ok);
}
