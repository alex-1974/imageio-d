#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build/sentinel-cog"
mkdir -p "$build"
url=${1:-https://sentinel-cogs.s3.amazonaws.com/sentinel-s2-l2a-cogs/12/R/UU/2024/4/S2A_12RUU_20240421_0_L2A/B02.tif}
source="/vsicurl/$url"

if ! command -v gdalinfo >/dev/null 2>&1 || ! command -v gdal_translate >/dev/null 2>&1; then
    echo 'gdalinfo and gdal_translate are required' >&2
    exit 1
fi

# Metadata and a small native UInt16 window are the only remote reads. GDAL is
# an independent oracle here; this script does not define an imageio-d API.
gdalinfo -json --config GDAL_HTTP_MULTIRANGE YES "$source" > "$build/source.gdal.json"
gdal_translate -q --config GDAL_HTTP_MULTIRANGE YES -of ENVI -ot UInt16 \
    -srcwin 100 200 32 24 "$source" "$build/window"
mv "$build/window" "$build/window.raw"
gdalinfo -json --config GDAL_HTTP_MULTIRANGE YES "$source" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); b=d["bands"][0]; assert d["size"] == [10980,10980]; assert b["type"] == "UInt16"; assert d["geoTransform"][1] == 10.0 and d["geoTransform"][5] == -10.0; print("COG:", d["size"], b["type"], b["block"], d["geoTransform"])'

python3 - "$build/source.gdal.json" "$build/window.raw" <<'PY'
import hashlib
import json
import pathlib
import sys
metadata = json.load(open(sys.argv[1]))
window = pathlib.Path(sys.argv[2])
assert metadata["size"] == [10980, 10980]
assert metadata["bands"][0]["type"] == "UInt16"
assert window.stat().st_size == 32 * 24 * 2
print("window=100,200,32,24 bytes=", window.stat().st_size)
print("source-json-sha256=", hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
print("window-sha256=", hashlib.sha256(window.read_bytes()).hexdigest())
PY
