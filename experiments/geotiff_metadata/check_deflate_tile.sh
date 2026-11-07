#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
consumer="$root/../compression_consumer"
mkdir -p "$build"

"$root/oracle_fixture.sh" >/dev/null
fixture="$build/geotiff-metadata.tif"
gdal_translate -q -of ENVI -ot UInt16 "$fixture" "$build/geotiff-metadata.raw"
mv "$build/geotiff-metadata.raw" "$build/geotiff-metadata.raw.bin"

for compiler in dmd ldc2; do
    dub run --compiler="$compiler" --root="$consumer" -- \
        "$fixture" "$build/geotiff-metadata.raw.bin" 2
done

for compiler in dmd ldc2; do
    if [ "$compiler" = dmd ]; then version_flag=-version=WindowProbe
    else version_flag=-d-version=WindowProbe; fi
    dub run --compiler="$compiler" --root="$consumer" --config=window \
        -- "$fixture"
done

echo 'tiled UInt16 Deflate/ Predictor-2 decode passed under DMD/LDC'
