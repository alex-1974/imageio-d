#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
large="$build/large"
runs=${1:-3}
iterations=${2:-100}

"$root/large_fixture_generate.sh" >/dev/null

dmd -O -release -of="$build/tiff-planar-large-dmd" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_planar_oracle.d"
ldc2 -O3 -release -of="$build/tiff-planar-large-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_planar_oracle.d"
dmd -O -release -of="$build/tiff-tile-large-dmd" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_tile_oracle.d"
ldc2 -O3 -release -of="$build/tiff-tile-large-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_tile_oracle.d"

for compiler in dmd ldc; do
    echo "--- $compiler 1024x1024 planar ($runs runs) ---"
    i=1
    while [ "$i" -le "$runs" ]; do
        /usr/bin/time -f "path=planar compiler=$compiler run=$i elapsed=%e sec max_rss=%M KB" \
            "$build/tiff-planar-large-$compiler" "$large/rgb8-planar.tif" \
            "$large/rgb8-planar.raw" 1024 1024 "$iterations" >/dev/null
        i=$((i + 1))
    done
    echo "--- $compiler 1024x1024 tiled ($runs runs) ---"
    i=1
    while [ "$i" -le "$runs" ]; do
        /usr/bin/time -f "path=tiled compiler=$compiler run=$i elapsed=%e sec max_rss=%M KB" \
            "$build/tiff-tile-large-$compiler" "$large/gray16-tiled.tif" \
            "$large/gray16-tiled.raw" 1024 1024 256 256 "$iterations" >/dev/null
        i=$((i + 1))
    done
done
