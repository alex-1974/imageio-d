#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" \
        -of="$build/native-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_native_probe.d"
    "$build/native-$compiler" "$build/$compiler"
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" \
        -of="$build/io-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_io_probe.d"
    "$build/io-$compiler" "$build/$compiler-420.jpg" \
        "$build/$compiler-partial.jpg"
    test "$(wc -c < "$build/$compiler-partial.jpg")" -eq 11
done
for sampling in 444 422 420 gray; do
    cmp "$build/dmd-$sampling.jpg" "$build/ldc2-$sampling.jpg"
    magick identify "$build/dmd-$sampling.jpg" >/dev/null
done
python3 - "$build" <<'PY'
import pathlib
import sys
from PIL import Image

root = pathlib.Path(sys.argv[1])
for compiler in ("dmd", "ldc2"):
    for sampling in ("444", "422", "420"):
        with Image.open(root / f"{compiler}-{sampling}.jpg") as image:
            image.load()
            assert image.size == (17, 19) and image.mode == "RGB"
    with Image.open(root / f"{compiler}-gray.jpg") as image:
        image.load()
        assert image.size == (13, 7) and image.mode == "L"
    assert (root / f"{compiler}-partial.jpg").read_bytes() != \
        (root / f"{compiler}-420.jpg").read_bytes()
print("native planes / bounded I/O probes: pass")
PY
