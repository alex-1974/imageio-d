#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM

python3 - "$build/input.raw" <<'PY'
import pathlib, sys
w, h = 17, 19
data = bytearray()
for y in range(h):
    for x in range(w):
        data.extend(((x * 13 + y * 7) & 255, (x * 3 + y * 19) & 255,
                     (x * 29 + y * 5) & 255))
pathlib.Path(sys.argv[1]).write_bytes(data)
PY

for compiler in dmd ldc2; do
    dub build --root="$root" --compiler="$compiler" --build=release-nobounds
    "$root/imageio-public-jpeg-consumer" encode 17 19 3 \
        "$build/input.raw" "$build/output-$compiler.jpg" unused
    python3 - "$build/output-$compiler.jpg" <<'PY'
from PIL import Image
import sys
with Image.open(sys.argv[1]) as image:
    assert image.size == (17, 19)
    assert image.mode == "RGB"
PY
    "$root/imageio-public-jpeg-consumer" decode 17 19 3 \
        "$build/output-$compiler.jpg" "$build/decoded-$compiler" unused
    test "$(wc -c < "$build/decoded-$compiler")" -eq 969
done
echo 'public JPEG consumer passed under DMD/LDC'
