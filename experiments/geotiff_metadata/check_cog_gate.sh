#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build/cog-gate"
mkdir -p "$build"

"$root/check_range_source.sh"
"$root/check_deflate_tile.sh"
"$root/check_overviews.sh"
"$root/sentinel_cog_compare.sh"

cp "$root/.build/geotiff-metadata.tif" "$build/truncated.tif"
size=$(wc -c < "$build/truncated.tif")
truncate -s $((size / 2)) "$build/truncated.tif"
if gdal_translate -q -of ENVI "$build/truncated.tif" "$build/truncated-window" >/dev/null 2>&1; then
    echo 'truncated fixture was unexpectedly accepted' >&2
    exit 1
fi
echo 'negative: truncated fixture rejected'

python3 - "$build/manifest.txt" <<'PY'
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
p.write_text("range_source=bounded-local\nwindow=7x6@3,2\noverviews=2x,4x\nnegative=truncated-rejected\n")
print(p.read_text(), end="")
PY
printf '%s\n' 'COG range gate orchestration passed'
