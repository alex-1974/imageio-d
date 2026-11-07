module sample_oracle;

enum Status { ok, truncated }
struct U16Result { Status status; ushort value; }
struct U32Result { Status status; uint value; }

U16Result readU16(const(ubyte)[] bytes, bool little) @safe pure nothrow @nogc
{
    if (bytes.length < 2) return U16Result(Status.truncated);
    return U16Result(Status.ok, little
        ? cast(ushort)(bytes[0] | bytes[1] << 8)
        : cast(ushort)(bytes[0] << 8 | bytes[1]));
}

U32Result readU32(const(ubyte)[] bytes, bool little) @safe pure nothrow @nogc
{
    if (bytes.length < 4) return U32Result(Status.truncated);
    return U32Result(Status.ok, little
        ? cast(uint)(bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24)
        : cast(uint)(bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]));
}

@safe @nogc nothrow
void main()
{
    ubyte[2] little16 = [0x34, 0x12];
    ubyte[2] big16 = [0x12, 0x34];
    assert(readU16(little16[], true).value == 0x1234);
    assert(readU16(big16[], false).value == 0x1234);
    ubyte[4] little32 = [0x78, 0x56, 0x34, 0x12];
    ubyte[4] big32 = [0x12, 0x34, 0x56, 0x78];
    assert(readU32(little32[], true).value == 0x12345678);
    assert(readU32(big32[], false).value == 0x12345678);
    assert(readU32(little32[][0 .. 3], true).status == Status.truncated);
}
