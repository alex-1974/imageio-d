import imageio : decodeRegion, inspect, writePng, PngWriteInfo,
    ImageWriteOptions, MetadataPolicy;
import transport : FileSource, FileSink;

int main(string[] args)
{
    if (args.length != 3) return 2;
    auto source = new FileSource(args[1]);
    auto inspected = inspect(source);
    if (!inspected.ok) return 1;
    auto decoded = decodeRegion(source, 0, 0, inspected.info.width, inspected.info.height);
    if (!decoded.ok || decoded.region.info.componentCount != 1
        || decoded.region.data.length != inspected.info.width * inspected.info.height)
        return 1;
    auto processed = new ubyte[](decoded.region.data.length);
    foreach (size_t i, ubyte value; decoded.region.data)
        processed[i] = 255 - value;
    auto sink = new FileSink(args[2]);
    auto result = writePng(sink, PngWriteInfo(inspected.info.width,
        inspected.info.height, 8, 0), processed[], inspected.info.width,
        ImageWriteOptions(MetadataPolicy.rejectLoss, size_t.max));
    sink.close();
    return result.complete ? 0 : 1;
}
