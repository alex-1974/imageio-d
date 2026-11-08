import std.file : read;
import std.conv : to;
import imageio : TiffWriteInfo, TiffWriteMetadata, writeClassicTiff;
import transport : FileSink;

int main(string[] args)
{
    if (args.length != 7)
        return 2;
    const width = to!uint(args[1]);
    const height = to!uint(args[2]);
    const channels = to!ubyte(args[3]);
    const sampleBytes = to!ubyte(args[4]);
    auto pixels = cast(ubyte[])read(args[5]);
    auto sink = new FileSink(args[6]);
    auto result = writeClassicTiff(sink,
        TiffWriteInfo(width, height, channels, sampleBytes),
        pixels[], width * channels * sampleBytes);
    return result.complete ? 0 : 1;
}
