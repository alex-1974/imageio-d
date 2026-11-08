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
    "$root/imageio-public-png-consumer" encode 17 19 3 \
        "$build/input.raw" "$build/output-$compiler.png" unused
    python3 - "$build/output-$compiler.png" <<'PY'
from PIL import Image
import sys
with Image.open(sys.argv[1]) as image:
    assert image.size == (17, 19)
    assert image.mode == "RGB"
    image.verify()
PY
    "$root/imageio-public-png-consumer" decode 17 19 3 \
        "$build/output-$compiler.png" "$build/decoded-$compiler" unused
    cmp "$build/input.raw" "$build/decoded-$compiler"
done
echo 'public PNG consumer passed under DMD/LDC'
