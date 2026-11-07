module workspace_boundary_probe;

import block_bridge : Block;
import compressed_strip_bridge : decodePackBitsStrips;
import compressed_tile_bridge : decodePackBitsTiles;
import payload_decode : DecodeStatus, Layout;

void main()
{
    // One literal PackBits run containing a 3x2, one-band, 8-bit strip.
    ubyte[] stripFile = [5, 10, 11, 12, 13, 14, 15];
    Block[1] strips = [Block(0, cast(uint) stripFile.length)];
    ubyte[6] stripOutput;
    ubyte[6] exactStripScratch;
    assert(decodePackBitsStrips(stripFile[], strips[], 3, 2, 2, 1, 1,
        stripOutput[], exactStripScratch[], Layout(3, 1, 1)) == DecodeStatus.ok);
    ubyte[5] shortStripScratch;
    assert(decodePackBitsStrips(stripFile[], strips[], 3, 2, 2, 1, 1,
        stripOutput[], shortStripScratch[], Layout(3, 1, 1)) ==
        DecodeStatus.workspaceTooSmall);
    ubyte[5] shortStripOutput;
    assert(decodePackBitsStrips(stripFile[], strips[], 3, 2, 2, 1, 1,
        shortStripOutput[], exactStripScratch[], Layout(3, 1, 1)) ==
        DecodeStatus.destinationTooSmall);

    // A 2x2 visible image in a 4x4 logical tile. The workspace must cover the
    // padded logical tile, not merely the visible 2x2 edge.
    ubyte[] tileFile = [15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
    Block[1] tiles = [Block(0, cast(uint) tileFile.length)];
    ubyte[4] tileOutput;
    ubyte[16] exactTileScratch;
    assert(decodePackBitsTiles(tileFile[], tiles[], 2, 2, 4, 4, 1, 1,
        tileOutput[], exactTileScratch[], Layout(2, 1, 1)) == DecodeStatus.ok);
    assert(tileOutput == [0, 1, 4, 5]);
    ubyte[15] shortTileScratch;
    assert(decodePackBitsTiles(tileFile[], tiles[], 2, 2, 4, 4, 1, 1,
        tileOutput[], shortTileScratch[], Layout(2, 1, 1)) ==
        DecodeStatus.workspaceTooSmall);
    ubyte[3] shortTileOutput;
    assert(decodePackBitsTiles(tileFile[], tiles[], 2, 2, 4, 4, 1, 1,
        shortTileOutput[], exactTileScratch[], Layout(2, 1, 1)) ==
        DecodeStatus.destinationTooSmall);
}
