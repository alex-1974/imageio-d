#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
runs=${1:-5}

case "$runs" in
    ''|*[!0-9]*) echo "runs must be a positive integer" >&2; exit 2 ;;
esac
[ "$runs" -gt 0 ] || exit 2

planar="$build/oracle-rgb8-planar.tif"
rgbRaw="$build/oracle-rgb8.raw"
tile="$build/oracle-gray16-tiled.tif"
tileRaw="$build/oracle-gray16-tiled.raw"

for compiler in dmd ldc; do
    suffix=""
    [ "$compiler" = ldc ] && suffix="-ldc"
    echo "--- $compiler planar repeated ($runs runs) ---"
    i=1
    while [ "$i" -le "$runs" ]; do
        /usr/bin/time -f "path=planar run=$i elapsed=%e sec max_rss=%M KB" \
            "$build/tiff-planar-oracle$suffix" "$planar" "$rgbRaw" >/dev/null
        i=$((i + 1))
    done
    echo "--- $compiler tiled repeated ($runs runs) ---"
    i=1
    while [ "$i" -le "$runs" ]; do
        /usr/bin/time -f "path=tiled run=$i elapsed=%e sec max_rss=%M KB" \
            "$build/tiff-tile-oracle$suffix" "$tile" "$tileRaw" >/dev/null
        i=$((i + 1))
    done
done
