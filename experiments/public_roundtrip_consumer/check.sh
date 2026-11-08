#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM
python3 - "$build/input.pgm" <<'PY'
import pathlib, sys
w, h = 19, 11
data = bytes((x * 11 + y * 17) & 255 for y in range(h) for x in range(w))
pathlib.Path(sys.argv[1]).write_bytes(b"P5\n19 11\n255\n" + data)
PY
gdal_translate -q -of GTiff -co COMPRESS=DEFLATE "$build/input.pgm" "$build/input.tif"
for compiler in dmd ldc2; do
    dub run --root="$root" --compiler="$compiler" --build=release-nobounds \
        -- "$build/input.tif" "$build/output-$compiler.png"
    python3 - "$build/output-$compiler.png" <<'PY'
from PIL import Image
import sys
with Image.open(sys.argv[1]) as image:
    assert image.size == (19, 11)
    assert image.mode == "L"
    pixels = list(image.getdata())
    assert pixels[0] == 255 and pixels[-1] == 255 - ((18 * 11 + 10 * 17) & 255)
PY
done
echo 'public TIFF-to-PNG roundtrip consumer passed under DMD/LDC'
