import std.file : read, write;
import std.conv : to;
import std.stdio : writeln;
import compression.deflate : InflateWorkspace;
import imageio : PngWriteInfo, writePng, readPng, ImageWriteOptions,
    MetadataPolicy;
import transport : FileSink;

int main(string[] args)
{
    if (args.length != 8)
        return 2;
    const width = to!uint(args[2]);
    const height = to!uint(args[3]);
    auto input = cast(ubyte[])read(args[5]);
    if (args[1] == "encode")
    {
        auto sink = new FileSink(args[6]);
        auto result = writePng(sink, PngWriteInfo(width, height, 8, 2),
            input[], width * 3,
            ImageWriteOptions(MetadataPolicy.rejectLoss, 16 * 1024 * 1024));
        sink.close();
        return result.complete ? 0 : 1;
    }
    if (args[1] == "decode")
    {
        auto output = new ubyte[](cast(size_t)width * height * 3);
        InflateWorkspace workspace;
        auto result = readPng(input[], output[], width * 3, workspace);
        if (!result.complete || result.bytesProduced != output.length)
        {
            writeln("PNG decode failed: ", result.error, " bytes=", result.bytesProduced);
            return 1;
        }
        write(args[6], output[]);
        return 0;
    }
    return 2;
}
