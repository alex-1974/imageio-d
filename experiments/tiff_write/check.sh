#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
gdalinfo --version
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -of="$build/writer-$compiler" \
        -I="$root/source" "$root/source/tiff_write_research.d" \
        "$root/source/oracle.d"
    for channels in 1 2 3 4; do
        for bytes in 1 2; do
            raw="$build/$channels-$bytes.raw"
            python3 "$root/oracle.py" prepare "$raw" 19 11 "$channels" "$bytes"
            tif="$build/$channels-$bytes-$compiler.tif"
            "$build/writer-$compiler" 19 11 "$channels" "$bytes" "$raw" "$tif"
            python3 "$root/oracle.py" verify "$tif" "$raw" 19 11 "$channels" "$bytes"
            if [ "$channels" -eq 4 ] && [ "$bytes" -eq 2 ]; then
                sha256sum "$raw" "$tif"
            fi
        done
    done
done
echo 'Classic TIFF write research oracle passed under DMD/LDC'
