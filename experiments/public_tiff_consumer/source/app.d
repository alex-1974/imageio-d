import std.stdio : writeln;
import imageio : decodeRegion, decodeRegionAtBestLevel, decodeRegionAtLevel,
    inspect, inspectLevels;
import transport : FileSource;

int main(string[] args)
{
    if (args.length != 2)
        return 2;
    auto source = new FileSource(args[1]);
    auto info = inspect(source);
    if (!info.ok)
    {
        writeln("public inspection failed: ", info.error);
        return 1;
    }
    writeln("public info: ", info.info.width, "x", info.info.height,
        " compression=", info.info.compression, " tile=", info.info.tileWidth,
        "x", info.info.tileLength, " count=", info.info.tileCount,
        " offsetType=", info.info.tileOffsetType, " countType=",
        info.info.tileByteCountType, " predictor=", info.info.predictor);
    auto result = decodeRegion(source, 3, 2, 7, 6);
    if (!result.ok)
    {
        writeln("public decoder failed: ", result.error);
        return 1;
    }
    auto selected = decodeRegionAtLevel(source, 0, 3, 2, 7, 6);
    if (!selected.ok || selected.region.data != result.region.data)
    {
        writeln("selected level decode failed: ", selected.error);
        return 1;
    }
    auto levels = inspectLevels(source);
    if (!levels.ok)
        return 1;
    auto best = decodeRegionAtBestLevel(source, 0, 0, 17, 13, 7, 6);
    if (!best.ok)
    {
        writeln("best-level decode failed: ", best.error);
        return 1;
    }
    writeln("levels=", levels.levels.length, " best=",
        best.region.info.width, "x", best.region.info.height);
    writeln("public decoder: ", result.region.info.width, "x",
        result.region.info.height, " components=",
        result.region.info.componentCount, " bytes=",
        result.region.data.length);
    return 0;
}
