module tile_benchmark;

import std.datetime.stopwatch : StopWatch;
import std.random : Random, unpredictableSeed, uniform;
import std.stdio : writefln;
import block_bridge : Block, decodeTiles;
import payload_decode : DecodeStatus, Layout;
import tuning : defaultTuning;

void runCase(uint width, uint height, uint tileSize)
{
    auto tilesX = (width + tileSize - 1) / tileSize;
    auto tilesY = (height + tileSize - 1) / tileSize;
    auto tileBytes = cast(size_t) tileSize * tileSize;
    auto fileBytes = new ubyte[tileBytes * tilesX * tilesY];
    auto random = Random(unpredictableSeed);
    foreach (ref value; fileBytes) value = uniform!ubyte(random);
    auto blocks = new Block[tilesX * tilesY];
    foreach (i; 0 .. blocks.length)
        blocks[i] = Block(cast(uint) (i * tileBytes), cast(uint) tileBytes);
    auto destination = new ubyte[cast(size_t) width * height];
    StopWatch watch;
    watch.start();
    ulong checksum;
    foreach (iteration; 0 .. 20)
    {
        auto status = decodeTiles(fileBytes[], blocks[], width, height,
            tileSize, tileSize, 1, 1, destination[], Layout(width, 1, 1));
        assert(status == DecodeStatus.ok);
        foreach (value; destination) checksum += value;
    }
    writefln("tile=%s size=%sx%s ms=%s checksum=%s", tileSize, width, height,
        watch.peek.total!"msecs", checksum);
}

void main()
{
    auto tuning = defaultTuning();
    runCase(1024, 1024, tuning.tileWidth);
    runCase(1024, 1024, 16);
    runCase(1024, 1024, 32);
    runCase(1024, 1024, 64);
    runCase(1024, 1024, 128);
    runCase(1024, 1024, 256);
}
