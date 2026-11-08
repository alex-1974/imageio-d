import std.file : read, write;
import std.conv : to;
import compression.jpeg : Sampling;
import imageio : JpegWriteInfo, writeJpeg, readJpeg,
    ImageWriteOptions, MetadataPolicy;
import transport : FileSink;

int main(string[] args)
{
    if (args.length != 8)
        return 2;
    const width = to!uint(args[2]);
    const height = to!uint(args[3]);
    const components = to!ubyte(args[4]);
    auto input = cast(ubyte[])read(args[5]);
    if (args[1] == "encode")
    {
        auto sink = new FileSink(args[6]);
        auto result = writeJpeg(sink, JpegWriteInfo(width, height, components),
            input[], width * components, 75, Sampling.s444,
            ImageWriteOptions(MetadataPolicy.rejectLoss, 16 * 1024 * 1024));
        return result.complete ? 0 : 1;
    }
    if (args[1] == "decode")
    {
        auto output = new ubyte[](cast(size_t)width * height * components);
        auto result = readJpeg(input[], output[], width * components);
        if (!result.complete || result.bytesProduced != output.length)
            return 1;
        write(args[6], output[]);
        return 0;
    }
    return 2;
}
