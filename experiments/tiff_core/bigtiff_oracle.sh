#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"
source_tiff=${1:?provide an independently generated TIFF fixture}
width=${2:?provide expected width from GDAL}
height=${3:?provide expected height from GDAL}
gdal_translate -q -of GTiff -co BIGTIFF=YES "$source_tiff" "$build/bigtiff-oracle.tif"
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -of="$build/bigtiff-oracle-$compiler" \
        "$root/source/bigtiff_header.d" "$root/source/bigtiff_oracle.d"
    "$build/bigtiff-oracle-$compiler" "$build/bigtiff-oracle.tif" "$width" "$height"
done
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -of="$build/bigtiff-sparse-$compiler" \
        "$root/source/bigtiff_header.d" "$root/source/bigtiff_sparse_probe.d"
    "$build/bigtiff-sparse-$compiler" "$build/bigtiff-sparse-$compiler.tif"
done
echo 'BigTIFF GDAL metadata and >4-GiB sparse IFD probes passed under DMD/LDC'
