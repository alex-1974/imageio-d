#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build/range-decode"
consumer="$root/../compression_consumer"
mkdir -p "$build"

"$root/oracle_fixture.sh" >/dev/null
source="$root/.build/geotiff-metadata.tif"
range_tiff="$build/range-fixture.tif"
gdal_translate -q -of GTiff -co BIGTIFF=YES -co TILED=YES \
    -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 -co COMPRESS=DEFLATE \
    -co PREDICTOR=2 "$source" "$range_tiff"
gdal_translate -q -of ENVI -ot UInt16 "$range_tiff" "$build/range-fixture.raw"
mv "$build/range-fixture.raw" "$build/range-fixture.raw.bin"

# The bridge reads IFD, offset/count and compressed tile data as separate
# ranges. It does not construct a full encoded-file byte slice.
sh "$consumer/check-bigtiff-ranges.sh" "$range_tiff" "$build/range-fixture.raw.bin"
printf '%s\n' 'range-backed Deflate decode gate passed'
