module float_oracle;

struct FloatBits { uint bits; }

@trusted pure nothrow @nogc
FloatBits bitsOf(float value)
{
    union Reinterpret { float value; uint bits; }
    Reinterpret r;
    r.value = value;
    return FloatBits(r.bits);
}

@trusted pure nothrow @nogc
float valueOf(FloatBits bits)
{
    union Reinterpret { float value; uint bits; }
    Reinterpret r;
    r.bits = bits.bits;
    return r.value;
}

@safe @nogc nothrow
void main()
{
    auto one = bitsOf(1.0f);
    assert(one.bits == 0x3f800000);
    assert(bitsOf(valueOf(one)).bits == one.bits);
    auto negative = bitsOf(-2.5f);
    assert(bitsOf(valueOf(negative)).bits == negative.bits);
}
