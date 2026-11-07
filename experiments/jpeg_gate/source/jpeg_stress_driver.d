module jpeg_stress_driver;

import std.conv : to;
import std.exception : enforce;
import std.file : read, write;
import std.stdio : writeln;
import jpeg_research;

void main(string[] args)
{
    enforce(args.length == 9);
    const width = to!uint(args[3]);
    const height = to!uint(args[4]);
    const channels = to!ubyte(args[5]);
    const quality = to!ubyte(args[6]);
    const sampling = args[7] == "420" ? Sampling.s420 :
        args[7] == "422" ? Sampling.s422 : Sampling.s444;
    const restart = to!ushort(args[8]);
    auto raw = cast(ubyte[])read(args[1]);
    enforce(raw.length == cast(size_t)width * height * channels);
    const h = sampling == Sampling.s444 ? 1 : 2;
    const v = sampling == Sampling.s420 ? 2 : 1;
    const mcuCount = ((width + 8 * h - 1) / (8 * h)) *
        ((height + 8 * v - 1) / (8 * v));
    const blocks = channels == 1 ? 1 : h * v + 2;
    auto output = new ubyte[1024 + mcuCount * blocks * 512];
    auto result = encodeJpeg(Info(width, height, channels), raw[],
        width * channels, output[], EncodeOptions(quality, sampling, restart));
    enforce(result.ok, "JPEG encode failed");
    auto reopened = new ubyte[raw.length];
    auto decoded = decodeJpeg(output[0 .. result.written], reopened[],
        width * channels);
    enforce(decoded.ok && decoded.written == raw.length,
        "JPEG self-decode failed");
    // The chroma post-pass must honour a caller stride, not only packed rows.
    const stride = cast(size_t)width * channels + 7;
    auto padded = new ubyte[cast(size_t)height * stride + 2];
    padded[] = 0xa5;
    auto paddedResult = decodeJpeg(output[0 .. result.written],
        padded[1 .. $ - 1], stride);
    enforce(paddedResult.ok && paddedResult.written == raw.length,
        "JPEG padded-stride decode failed");
    enforce(padded[0] == 0xa5 && padded[$ - 1] == 0xa5,
        "JPEG destination canary changed");
    foreach (size_t y; 0 .. height)
    {
        const rowBytes = cast(size_t)width * channels;
        enforce(padded[1 + y * stride .. 1 + y * stride + rowBytes] ==
            reopened[y * rowBytes .. (y + 1) * rowBytes],
            "JPEG padded-stride pixels differ");
        foreach (value; padded[1 + y * stride + rowBytes .. 1 + (y + 1) * stride])
            enforce(value == 0xa5, "JPEG row padding changed");
    }
    write(args[2], output[0 .. result.written]);
    write(args[2] ~ ".decoded.raw", reopened[]);
    writeln(args[2], " encoded_bytes=", result.written);
}
