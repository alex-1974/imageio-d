#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM

python3 - "$build/input.raw" <<'PY'
import pathlib, sys
width, height, channels, sample_bytes = 19, 11, 3, 2
mask = (1 << (8 * sample_bytes)) - 1
data = bytearray()
for y in range(height):
    for x in range(width):
        for c in range(channels):
            data.extend(((x * 139 + y * 773 + c * 3271) & mask).to_bytes(
                sample_bytes, "little"))
pathlib.Path(sys.argv[1]).write_bytes(data)
PY

for compiler in dmd ldc2; do
    dub build --root="$root" --compiler="$compiler" --build=release-nobounds
    "$root/imageio-public-tiff-write-consumer" 19 11 3 2 \
        "$build/input.raw" "$build/output-$compiler.tif" metadata
    gdal_translate -q -of ENVI -ot UInt16 -co INTERLEAVE=BIP \
        "$build/output-$compiler.tif" "$build/decoded-$compiler"
    cmp "$build/input.raw" "$build/decoded-$compiler"
    report=$(gdalinfo "$build/output-$compiler.tif")
    echo "$report" | grep -F "Size is 19, 11" >/dev/null
    test "$(echo "$report" | grep -c '^Band ')" -eq 3
    echo "$report" | grep -F "Type=UInt16" >/dev/null
    echo "$report" | grep -F "NoData Value=-9999" >/dev/null
    "$root/imageio-public-tiff-write-consumer" 19 11 3 2 \
        "$build/input.raw" "$build/big-$compiler.tif" big
    bigReport=$(gdalinfo "$build/big-$compiler.tif")
    echo "$bigReport" | grep -F "Size is 19, 11" >/dev/null
    echo "$bigReport" | grep -F "Type=UInt16" >/dev/null
done
echo 'public TIFF write consumer passed under DMD/LDC'
