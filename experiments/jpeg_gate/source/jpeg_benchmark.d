module jpeg_benchmark;

import core.time : MonoTime;
import std.conv : to;
import std.exception : enforce;
import std.file : read, write;
import std.stdio : writeln;
import jpeg_research;

/// One warmed, allocation-free encode and decode measurement per invocation.
/// The process/startup, input reads, output writes and checksum are untimed.
void main(string[] args)
{
    enforce(args.length == 10 || args.length == 12,
        "usage: jpeg_benchmark raw reference.jpg out.jpg decoded.raw width height channels quality sampling [mode repetitions]");
    const mode = args.length == 12 ? args[10] : "both";
    const repetitions = args.length == 12 ? to!uint(args[11]) : 1U;
    enforce((mode == "both" || mode == "encode" || mode == "decode") &&
        repetitions > 0 && repetitions <= 100);
    const width = to!uint(args[5]);
    const height = to!uint(args[6]);
    const channels = to!ubyte(args[7]);
    const quality = to!ubyte(args[8]);
    const sampling = args[9] == "420" ? Sampling.s420 :
        args[9] == "422" ? Sampling.s422 : Sampling.s444;
    enforce(args[9] == "444" || args[9] == "422" || args[9] == "420");
    auto source = cast(ubyte[])read(args[1]);
    auto reference = cast(ubyte[])read(args[2]);
    enforce(source.length == cast(size_t)width * height * channels);
    const size_t hFactor = sampling == Sampling.s444 ? 1 : 2;
    const size_t vFactor = sampling == Sampling.s420 ? 2 : 1;
    const mcuCount = ((cast(size_t)width + 8 * hFactor - 1) / (8 * hFactor)) *
        ((cast(size_t)height + 8 * vFactor - 1) / (8 * vFactor));
    const blocks = channels == 1 ? 1 : hFactor * vFactor + 2;
    const capacity = 1024 + mcuCount * blocks * 512;
    auto encoded = new ubyte[capacity];
    auto decoded = new ubyte[source.length];
    const options = EncodeOptions(quality, sampling);
    auto warmEncode = encodeJpeg(Info(width, height, channels), source[],
        width * channels, encoded[], options);
    enforce(warmEncode.ok, "JPEG warm-up encode failed");
    auto warmDecode = decodeJpeg(reference[], decoded[], width * channels);
    enforce(warmDecode.ok && warmDecode.written == source.length,
        "JPEG warm-up decode failed");

    auto result = warmEncode;
    auto decodedResult = warmDecode;
    long encodeNs, decodeNs;
    foreach (_; 0 .. repetitions)
    {
        if (mode != "decode")
        {
            const startEncode = MonoTime.currTime;
            result = encodeJpeg(Info(width, height, channels), source[],
                width * channels, encoded[], options);
            encodeNs += (MonoTime.currTime - startEncode).total!"nsecs";
            enforce(result.ok, "JPEG timed encode failed");
        }
        if (mode != "encode")
        {
            const startDecode = MonoTime.currTime;
            decodedResult = decodeJpeg(reference[], decoded[], width * channels);
            decodeNs += (MonoTime.currTime - startDecode).total!"nsecs";
            enforce(decodedResult.ok && decodedResult.written == source.length,
                "JPEG timed decode failed");
        }
    }

    ulong checksum;
    foreach (value; decoded) checksum += value;
    if (args[3] != "-") write(args[3], encoded[0 .. result.written]);
    if (args[4] != "-") write(args[4], decoded[]);
    writeln(encodeNs / repetitions, " ", decodeNs / repetitions, " ", result.written, " ",
        checksum, " ", capacity);
}
