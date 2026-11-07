module range_decode;

import transport;
import bigtiff_range_bridge : Block64, decodeDeflateRanges;
import bigtiff_header : RangeWindow;
import deflate_bridge : ImageSpec, Layout, requirements, BridgeStatus;
import compression.deflate : InflateWorkspace;
import std.stdio : writefln;

void main(string[] args)
{
    assert(args.length > 1);
    auto source = new FileSource(args[1]);
    // The generated research fixture has one compressed 16x16 tile at 881.
    enum tileOffset = 392UL;
    enum tileBytes = 65;
    ubyte[tileBytes] encoded;
    auto fetched = source.read(ByteRange(tileOffset, tileBytes), encoded[]);
    assert(fetched.ok && fetched.bytesRead == tileBytes);

    // Decode the first 16x13 window; the second edge tile is intentionally not
    // requested, proving that the transport/decoder path is range-bounded.
    const spec = ImageSpec(16, 13, 1, 2, 16, 16, true, true, 2);
    const req = requirements(spec);
    assert(req.status == BridgeStatus.ok);
    Block64[1] blocks = [Block64(tileOffset, tileBytes)];
    RangeWindow[1] windows = [RangeWindow(tileOffset, encoded[])];
    ubyte[512] inflateScratch;
    ubyte[512] blockPixels;
    ubyte[416] output;
    InflateWorkspace decoder;
    const result = decodeDeflateRanges(blocks[], windows[], spec, decoder,
        inflateScratch[], blockPixels[], output[], Layout(32, 2, 2));
    assert(result.status == BridgeStatus.ok);
    // The first sample is generated as x*257 + y*4099 and stored little-endian.
    assert(output[0] == 0 && output[1] == 0);
    writefln("transport to decoder: fetched=%s decoded=%s blocks=%s",
        fetched.bytesRead, output.length, result.blocksWritten);
}
