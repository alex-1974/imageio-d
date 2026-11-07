module window_main;

import deflate_bridge;
import tiff_metadata;
import compression.deflate : InflateWorkspace;
import std.file : read;
import std.stdio : writefln;

void main(string[] args)
{
    assert(args.length >= 2);
    auto file = cast(const(ubyte)[]) read(args[1]);
    TiffInfo info;
    assert(inspectTiff(file, info) == BridgeStatus.ok);
    auto blocks = new Block[requirements(info.spec).blockCount];
    assert(readBlocks(file, info, blocks) == BridgeStatus.ok);
    const window = PixelWindow(3, 2, 7, 6);
    auto output = new ubyte[window.width * window.height * info.spec.bands * info.spec.sampleBytes];
    auto scratch = new ubyte[requirements(info.spec).scratchBytes];
    InflateWorkspace decoder;
    const layout = Layout(window.width * info.spec.bands * info.spec.sampleBytes,
        info.spec.bands * info.spec.sampleBytes, info.spec.sampleBytes);
    WindowReport report;
    const result = decodeDeflateWindowReported(file, blocks, info.spec, window,
        decoder, scratch, output, layout, report);
    assert(result.ok && result.blocksWritten == 1);
    assert(report.path == DecodePath.nativeBlocks);
    assert(report.decodedX == 3 && report.decodedY == 2);
    assert(report.decodedWidth == 7 && report.decodedHeight == 6);
    assert(report.decodedBlocks == 1 && report.compressedBytes != 0);
    foreach (i; 0 .. output.length / 2)
    {
        const x = window.x + (i % window.width);
        const y = window.y + (i / window.width);
        const expected = cast(ushort)((x * 257 + y * 4099) & 0xffff);
        const actual = cast(ushort)(output[i * 2] | output[i * 2 + 1] << 8);
        assert(actual == expected);
    }
    writefln("window decode: %sx%s at %s,%s path=%s blocks=%s compressed=%s bytes=%s",
        window.width, window.height, window.x, window.y, report.path,
        report.decodedBlocks, report.compressedBytes, output.length);
}
