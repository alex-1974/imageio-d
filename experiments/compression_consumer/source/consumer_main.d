module consumer_main;
import deflate_bridge;
import tiff_metadata;
import compression.deflate : InflateWorkspace;
import compression.checksum : crc32;
import core.memory : GC;
import core.time : MonoTime;
import std.conv : to;
import std.file : read;
import std.stdio : writefln;

pragma(inline, false)
private BridgeResult decodeOnce(scope const(ubyte)[] file, scope const(Block)[] blocks,
    ImageSpec spec, ref InflateWorkspace decoder, scope ubyte[] scratch,
    scope ubyte[] output, Layout layout) @safe pure nothrow @nogc
{ return decodeDeflateBlocks(file, blocks, spec, decoder, scratch, output, layout); }

void main(string[] args)
{
    assert(args.length >= 3);
    auto file = cast(const(ubyte)[])read(args[1]);
    auto expected = cast(const(ubyte)[])read(args[2]);
    TiffInfo info;
    const inspected = inspectTiff(file, info);
    assert(inspected == BridgeStatus.ok);
    const req = requirements(info.spec);
    assert(req.status == BridgeStatus.ok && req.outputBytes == expected.length);
    auto blocks = new Block[req.blockCount];
    const planned = readBlocks(file, info, blocks);
    assert(planned == BridgeStatus.ok);
    auto output = new ubyte[req.outputBytes];
    auto scratch = new ubyte[req.scratchBytes];
    InflateWorkspace decoder;
    const layout = Layout(cast(size_t)info.spec.width * info.spec.bands * info.spec.sampleBytes,
        info.spec.bands * info.spec.sampleBytes, info.spec.sampleBytes);
    const warmup = decodeOnce(file, blocks, info.spec, decoder, scratch, output, layout);
    assert(warmup.ok);
    assert(output == expected);
    const iterations = args.length > 3 ? to!uint(args[3]) : 1;
    const fresh = args.length > 4 && args[4] == "fresh";
    const before = GC.allocatedInCurrentThread;
    const start = MonoTime.currTime;
    ulong checksum;
    foreach (iteration; 0 .. iterations)
    {
        if (fresh) decoder = InflateWorkspace.init;
        const result = decodeOnce(file, blocks, info.spec, decoder, scratch, output, layout);
        assert(result.ok);
        checksum += crc32(output) + iteration;
    }
    const seconds = (MonoTime.currTime - start).total!"nsecs" / 1e9;
    const allocated = GC.allocatedInCurrentThread - before;
    assert(output == expected && allocated == 0 && iterations > 0);
    writefln("TIFF mode=%s bytes=%s blocks=%s scratch=%s decoder=%s iterations=%s MBps=%.3f gcBytes=%s checksum=%s",
        fresh ? "fresh" : "reuse", output.length, blocks.length, scratch.length, decoder.sizeof,
        iterations, output.length * cast(double)iterations / seconds / 1e6, allocated, checksum);
}
