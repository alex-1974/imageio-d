module tuning;

struct Tuning
{
    uint tileWidth;
    uint tileHeight;
}

Tuning defaultTuning() @safe pure nothrow @nogc
{
    version (DigitalMars)
        return Tuning(128, 128);
    else version (LDC)
        return Tuning(64, 64);
    else
        return Tuning(64, 64);
}
