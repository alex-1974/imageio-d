#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"
run_build=$(mktemp -d "$build/bigtiff-ranges.XXXXXX")
trap 'rm -rf -- "$run_build"' EXIT HUP INT TERM
source_tiff=${1:?provide original TIFF fixture}
expected=${2:?provide GDAL raw pixel oracle}
for layout in strip tile; do
    if [ "$layout" = tile ]; then
        gdal_translate -q -of GTiff -co BIGTIFF=YES -co COMPRESS=DEFLATE \
            -co TILED=YES -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 \
            "$source_tiff" "$run_build/bigtiff-$layout.tif"
    else
        gdal_translate -q -of GTiff -co BIGTIFF=YES -co COMPRESS=DEFLATE \
            -co TILED=NO "$source_tiff" "$run_build/bigtiff-$layout.tif"
    fi
    for compiler in dmd ldc2; do
        if [ "$compiler" = dmd ]; then version_flag=-version=BigTiffRangeOracle
        else version_flag=-d-version=BigTiffRangeOracle; fi
        "$compiler" -w -dip1000 "$version_flag" -i \
            -I="$root/../../../../../compression-d/source" \
            -I="$root/source" -I="$root/../tiff_core/source" \
            -of="$run_build/bigtiff-range-$compiler" "$root/source/bigtiff_range_oracle.d"
        "$run_build/bigtiff-range-$compiler" "$run_build/bigtiff-$layout.tif" "$expected"
    done
done
echo 'BigTIFF strip/tile range consumer passed under DMD/LDC'
