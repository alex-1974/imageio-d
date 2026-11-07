#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
python3 "$root/stress_oracle.py" generate "$build"
for compiler in dmd ldc2; do
    "$compiler" -O -release -boundscheck=on -dip1000 -I="$root/source" \
        -of="$build/jpeg-stress-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_stress_driver.d"
    "$build/jpeg-stress-$compiler" "$build/gray-single.raw" \
        "$build/gray-single-$compiler.jpg" 1 1 1 100 444 0
    "$build/jpeg-stress-$compiler" "$build/rgb-thin.raw" \
        "$build/rgb-thin-$compiler.jpg" 1 19 3 95 420 1
    "$build/jpeg-stress-$compiler" "$build/rgb-edge.raw" \
        "$build/rgb-edge-$compiler.jpg" 17 19 3 95 420 1
    "$build/jpeg-stress-$compiler" "$build/rgb-edge-422.raw" \
        "$build/rgb-edge-422-$compiler.jpg" 17 19 3 95 422 1
    "$build/jpeg-stress-$compiler" "$build/rgb-gradient.raw" \
        "$build/rgb-gradient-$compiler.jpg" 257 193 3 85 420 7
    "$build/jpeg-stress-$compiler" "$build/rgb-texture.raw" \
        "$build/rgb-texture-$compiler.jpg" 256 256 3 95 444 13
    python3 "$root/stress_oracle.py" verify "$build" "$compiler"
done
for name in gray-single rgb-thin rgb-edge rgb-edge-422 rgb-gradient rgb-texture; do
    cmp "$build/$name-dmd.jpg" "$build/$name-ldc2.jpg"
done
