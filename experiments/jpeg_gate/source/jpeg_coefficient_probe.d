module jpeg_coefficient_probe;

import jpeg_research;
import std.conv : to;
import std.exception : enforce;
import std.file : read, write;

// Internal diagnosis only: the trace follows MCU order, then Y blocks, Cb, Cr.
void main(string[] args)
{
    enforce(args.length == 10,
        "usage: probe raw width height channels quality sampling jpeg samples coefficients");
    const width = to!uint(args[2]);
    const height = to!uint(args[3]);
    const channels = to!ubyte(args[4]);
    const quality = to!ubyte(args[5]);
    enforce(args[6] == "444" || args[6] == "422" || args[6] == "420");
    const sampling = args[6] == "420" ? Sampling.s420 :
        args[6] == "422" ? Sampling.s422 : Sampling.s444;
    auto raw = cast(ubyte[])read(args[1]);
    enforce(raw.length == cast(size_t)width * height * channels);
    const h = sampling == Sampling.s444 ? 1 : 2;
    const v = sampling == Sampling.s420 ? 2 : 1;
    const mcus = ((cast(size_t)width + 8 * h - 1) / (8 * h)) *
        ((cast(size_t)height + 8 * v - 1) / (8 * v));
    const blocks = channels == 1 ? 1 : h * v + 2;
    auto jpeg = new ubyte[1024 + mcus * blocks * 512];
    auto samples = new ubyte[mcus * blocks * 64];
    auto coefficients = new int[mcus * blocks * 64];
    jpeg[] = 0xa5;
    auto shortTrace = encodeJpeg(Info(width, height, channels), raw,
        width * channels, jpeg, EncodeOptions(quality, sampling),
        EncodeMetadata.init, Limits.init, samples[0 .. $ - 1], coefficients);
    enforce(shortTrace.status == Status.destinationTooSmall &&
        jpeg[0] == 0xa5 && jpeg[$ - 1] == 0xa5,
        "short trace modified JPEG destination");
    auto result = encodeJpeg(Info(width, height, channels), raw,
        width * channels, jpeg, EncodeOptions(quality, sampling),
        EncodeMetadata.init, Limits.init, samples, coefficients);
    enforce(result.ok, "JPEG probe encode failed");
    write(args[7], jpeg[0 .. result.written]);
    write(args[8], samples);
    write(args[9], cast(ubyte[])coefficients);
}
