module raw_checksum;

import std.file : read;
import std.stdio : writefln;

ulong checksum(const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    ulong value = 1469598103934665603UL;
    foreach (b; bytes)
    {
        value ^= b;
        value *= 1099511628211UL;
    }
    return value;
}

void main(string[] args)
{
    assert(args.length == 2);
    auto bytes = cast(const(ubyte)[]) read(args[1]);
    writefln("bytes=%s checksum=%s", bytes.length, checksum(bytes));
}
