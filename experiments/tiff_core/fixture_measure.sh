#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
tile="$build/oracle-gray16-tiled.tif"
tileRaw="$build/oracle-gray16-tiled.raw"
planar="$build/oracle-rgb8-planar.tif"
rgbRaw="$build/oracle-rgb8.raw"
gray="$build/oracle-gray8.tif"
grayRaw="$build/oracle-gray8.raw"
rgb="$build/oracle-rgb8.tif"
gray16="$build/oracle-gray16.tif"
gray16Raw="$build/oracle-gray16.raw"

if [ ! -x "$build/tiff-tile-oracle" ] || [ ! -x "$build/tiff-tile-oracle-ldc" ] \
    || [ ! -x "$build/tiff-strip-oracle" ] || [ ! -x "$build/tiff-strip-oracle-ldc" ]; then
    echo "run ./pixel_oracle.sh first" >&2
    exit 1
fi

for compiler in dmd ldc; do
    suffix=""
    [ "$compiler" = ldc ] && suffix="-ldc"
    echo "--- $compiler gray8 single strip ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' \
        "$build/tiff-strip-oracle$suffix" "$gray" "$grayRaw" >/dev/null
    echo "--- $compiler rgb8 single strip ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' \
        "$build/tiff-strip-oracle$suffix" "$rgb" "$rgbRaw" >/dev/null
    echo "--- $compiler gray16 single strip ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' \
        "$build/tiff-strip-oracle$suffix" "$gray16" "$gray16Raw" 2 >/dev/null
    echo "--- $compiler planar ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' \
        "$build/tiff-planar-oracle$suffix" "$planar" "$rgbRaw" 13 9 >/dev/null
    echo "--- $compiler tiled ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' \
        "$build/tiff-tile-oracle$suffix" "$tile" "$tileRaw" \
        19 11 16 16 >/dev/null
done
