import std.file : read;
import std.conv : to;
import imageio : TiffWriteInfo, TiffWriteMetadata, writeClassicTiff,
    ImageWriteOptions;
import transport : FileSink;

int main(string[] args)
{
    if (args.length != 8)
        return 2;
    const width = to!uint(args[1]);
    const height = to!uint(args[2]);
    const channels = to!ubyte(args[3]);
    const sampleBytes = to!ubyte(args[4]);
    auto pixels = cast(ubyte[])read(args[5]);
    auto sink = new FileSink(args[6]);
    immutable ushort[4] geoKeys = [1, 1, 0, 0];
    auto result = writeClassicTiff(sink,
        TiffWriteInfo(width, height, channels, sampleBytes),
        pixels[], width * channels * sampleBytes,
        ImageWriteOptions.init,
        args[7] == "metadata"
            ? TiffWriteMetadata(cast(const(ubyte)[])"-9999", geoKeys[])
            : TiffWriteMetadata.init);
    sink.close();
    return result.complete ? 0 : 1;
}
