module geotiff_inspection;

import std.file : read;
import std.stdio : writefln;
import ifd_result : parse, Status;

version (GeoTiffInspectionProbe)
void main(string[] args)
{
    assert(args.length > 1, "provide a GDAL-generated GeoTIFF fixture");
    auto bytes = cast(const(ubyte)[]) read(args[1]);
    auto result = parse(bytes);
    assert(result.status == Status.ok);
    assert(result.value.width == 17);
    assert(result.value.height == 13);
    assert(result.value.samplesPerPixel == 1);
    assert(result.value.bitsPerSample == 16);
    assert(result.value.compression == 8);
    assert(result.value.predictor == 2);
    assert(result.value.tileWidth == 16);
    assert(result.value.tileLength == 16);
    assert(result.value.modelPixelScale.count == 3);
    assert(result.value.modelTiepoint.count == 6);
    assert(result.value.geoKeyDirectory.count >= 4);
    assert(result.value.noData.count != 0);
    writefln("technical inspection: %sx%s UInt16 tiled=%sx%s predictor=%s GeoKeys=%s",
        result.value.width, result.value.height, result.value.tileWidth,
        result.value.tileLength, result.value.predictor,
        result.value.geoKeyDirectory.count);
}
