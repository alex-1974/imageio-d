module jpeg_malformed_probe;

import jpeg_research;
import std.conv : to;
import std.exception : enforce;
import std.file : read;
import std.stdio : writeln;

// Deterministic canary sweep over a real-content baseline JPEG. Mutations may
// still be valid JPEGs; the contract checked here is bounded failure/success.
void main(string[] args)
{
    enforce(args.length == 6,
        "usage: malformed-probe jpeg width height channels mutation-count");
    auto file = cast(ubyte[])read(args[1]);
    const width = to!uint(args[2]);
    const height = to!uint(args[3]);
    const channels = to!ubyte(args[4]);
    const count = to!uint(args[5]);
    enforce(count > 0 && count <= 256 && file.length > 4);
    auto destination = new ubyte[cast(size_t)width * height * channels + 2];
    auto baseline = decodeJpeg(file, destination[1 .. $ - 1], width * channels);
    enforce(baseline.ok && baseline.written == destination.length - 2);
    size_t[6] statusCounts;
    foreach (uint mutation; 0 .. count)
    {
        // Alternate header probes with evenly spaced full-file positions.
        const position = mutation % 2 == 0 ?
            cast(size_t)(mutation / 2) % (file.length < 128 ? file.length : 128) :
            cast(size_t)((cast(ulong)(mutation / 2) * file.length) / (count / 2));
        const original = file[position];
        file[position] ^= 0xff;
        destination[] = 0xa5;
        auto result = decodeJpeg(file, destination[1 .. $ - 1], width * channels);
        enforce(destination[0] == 0xa5 && destination[$ - 1] == 0xa5,
            "destination canary changed on byte mutation");
        ++statusCounts[cast(size_t)result.status];
        file[position] = original;
    }
    size_t truncations;
    foreach (length; [0UL, 1UL, 2UL, 3UL, 16UL, file.length / 4,
                      file.length / 2, file.length - 1])
    {
        if (length >= file.length) continue;
        destination[] = 0xa5;
        const result = decodeJpeg(file[0 .. length],
            destination[1 .. $ - 1], width * channels);
        enforce(!result.ok && destination[0] == 0xa5 &&
            destination[$ - 1] == 0xa5,
            "truncated JPEG was accepted or destination canary changed");
        ++truncations;
    }
    writeln("mutations=", count, " accepted=", statusCounts[Status.ok],
        " rejected=", count - statusCounts[Status.ok],
        " truncations_rejected=", truncations);
}
