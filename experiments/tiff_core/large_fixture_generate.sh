#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build/large"
mkdir -p "$build"

if ! command -v convert >/dev/null 2>&1 || ! command -v gdal_translate >/dev/null 2>&1; then
    echo "convert and gdal_translate are required" >&2
    exit 1
fi

convert -size 1024x1024 gradient:red-blue -depth 8 -compress None \
    "TIFF:$build/rgb8-strip.tif"
gdal_translate -q -of GTiff -co INTERLEAVE=BAND \
    "$build/rgb8-strip.tif" "$build/rgb8-planar.tif"
convert -size 1024x1024 gradient: -depth 16 \
    -define quantum:format=unsigned -compress None \
    -define tiff:tile-geometry=256x256 "TIFF:$build/gray16-tiled.tif"

for fixture in "$build"/*.tif; do
    echo "--- $(basename "$fixture") ---"
    gdalinfo "$fixture" | rg 'Size is|INTERLEAVE|Block=|Type=' || true
done

gdal_translate -q -of ENVI -co INTERLEAVE=BIP -ot Byte \
    "$build/rgb8-planar.tif" "$build/rgb8-planar.raw"
gdal_translate -q -of ENVI -ot UInt16 "$build/gray16-tiled.tif" "$build/gray16-tiled.raw"
echo "large fixtures generated in $build"
