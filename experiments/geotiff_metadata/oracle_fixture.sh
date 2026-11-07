#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

if ! command -v gdal_translate >/dev/null 2>&1 || ! command -v gdalinfo >/dev/null 2>&1; then
    echo "gdal_translate and gdalinfo are required" >&2
    exit 1
fi

python3 - "$build/source.pgm" <<'PY'
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
width, height = 17, 13
values = [(x * 257 + y * 4099) & 0xffff
          for y in range(height) for x in range(width)]
with path.open("wb") as f:
    f.write(f"P5\n{width} {height}\n65535\n".encode())
    for value in values:
        f.write(struct.pack(">H", value))
PY

python3 - "$build/source8.pgm" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
width, height = 17, 13
values = bytes((x * 13 + y * 29) & 0xff for y in range(height) for x in range(width))
with path.open("wb") as f:
    f.write(f"P5\n{width} {height}\n255\n".encode())
    f.write(values)
PY


# The source has no geospatial meaning. GDAL adds the technical GeoTIFF
# metadata used by the independent oracle and test fixture.
gdal_translate -q -ot UInt16 -a_srs EPSG:32612 \
    -a_ullr 300000 3400020 300170 3399890 \
    -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
    -co COMPRESS=DEFLATE -co PREDICTOR=2 \
    "$build/source.pgm" "$build/geotiff-metadata.tif"

gdal_edit.py -a_nodata 0 "$build/geotiff-metadata.tif"
gdalinfo -json "$build/geotiff-metadata.tif" > "$build/geotiff-metadata.gdal.json"

# Independent compression fixtures for the public imageio-d consumer. These
# codecs are implemented by compression-d; GDAL is only the fixture/oracle
# generator here.
gdal_translate -q -ot UInt16 -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
    -co COMPRESS=PACKBITS "$build/source.pgm" "$build/geotiff-packbits.tif"
gdal_translate -q -ot UInt16 -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
    -co COMPRESS=LZW -co PREDICTOR=2 "$build/source.pgm" "$build/geotiff-lzw.tif"
gdal_translate -q -ot UInt16 -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
    -co BIGTIFF=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 \
    "$build/source.pgm" "$build/geotiff-bigtiff.tif"
gdal_translate -q -ot Byte -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
    -co COMPRESS=JPEG -co JPEG_QUALITY=90 "$build/source8.pgm" "$build/geotiff-jpeg.tif"

# Keep a deliberately incomplete copy for truncation handling probes.
size=$(wc -c < "$build/geotiff-metadata.tif")
if [ "$size" -lt 2 ]; then
    echo "fixture unexpectedly tiny" >&2
    exit 1
fi
head -c $((size - 1)) "$build/geotiff-metadata.tif" > "$build/geotiff-metadata.truncated.tif"

sha256sum "$build/geotiff-metadata.tif" "$build/geotiff-metadata.gdal.json" \
    "$build/geotiff-metadata.truncated.tif" "$build/geotiff-packbits.tif" \
    "$build/geotiff-lzw.tif" "$build/geotiff-bigtiff.tif" "$build/geotiff-jpeg.tif"
printf '%s\n' "GeoTIFF metadata oracle fixture generated in $build"
