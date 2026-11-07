/// Independent malformed-input smoke probe; not a fuzz/security certificate.
module jpeg_external_corpus;

import jpeg_research;
import std.file : read;
import std.stdio : writeln;

void main(string[] args)
{
    assert(args.length >= 2);
    foreach (path; args[1 .. $])
    {
        auto file = cast(ubyte[])read(path);
        auto destination = new ubyte[100_000 + 32];
        destination[] = 0xa5;
        auto result = decodeJpeg(file[], destination[16 .. $ - 16],
            300, Limits(64 * 1024 * 1024, 10_000));
        assert(!result.ok);
        foreach (b; destination[0 .. 16]) assert(b == 0xa5);
        foreach (b; destination[$ - 16 .. $]) assert(b == 0xa5);
        writeln(path, " status=", result.status);
    }
}
