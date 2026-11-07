#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

dmd -version=PackBitsProbe -of="$build/packbits-dmd" -w -dip1000 \
    "$root/source/packbits.d"
"$build/packbits-dmd"
ldc2 -d-version=PackBitsProbe -of="$build/packbits-ldc" -w -dip1000 \
    "$root/source/packbits.d"
"$build/packbits-ldc"

dmd -version=BigTiffProbe -of="$build/bigtiff-dmd" -w -dip1000 \
    "$root/source/bigtiff_header.d"
"$build/bigtiff-dmd"
ldc2 -d-version=BigTiffProbe -of="$build/bigtiff-ldc" -w -dip1000 \
    "$root/source/bigtiff_header.d"
"$build/bigtiff-ldc"

dmd -of="$build/compression-negative-dmd" -w -dip1000 \
    "$root/source/packbits.d" "$root/source/compression_negative.d"
"$build/compression-negative-dmd"
ldc2 -of="$build/compression-negative-ldc" -w -dip1000 \
    "$root/source/packbits.d" "$root/source/compression_negative.d"
"$build/compression-negative-ldc"

echo "format gate probes passed: PackBits and BigTIFF header"
