#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

"$root/oracle_fixture.sh" >/dev/null
fixture="$build/geotiff-metadata.tif"
overview="$build/geotiff-metadata-overviews.tif"
gdal_translate -q "$fixture" "$overview"
gdaladdo -q -r nearest "$overview" 2 4
gdalinfo -json "$overview" > "$build/geotiff-metadata-overviews.gdal.json"

python3 - "$build/geotiff-metadata-overviews.gdal.json" <<'PY'
import json
import sys
d = json.load(open(sys.argv[1]))
b = d["bands"][0]
assert len(b["overviews"]) == 2
assert b["overviews"][0]["size"] == [9, 7]
assert b["overviews"][1]["size"] == [5, 4]
print("GDAL overview oracle:", [x["size"] for x in b["overviews"]])
PY

for compiler in dmd ldc2; do
    if [ "$compiler" = dmd ]; then version_flag=-version=OverviewProbe
    else version_flag=-d-version=OverviewProbe; fi
    "$compiler" -w -dip1000 "$version_flag" \
        -of="$build/overview-selection-$compiler" "$root/overview_selection.d"
    "$build/overview-selection-$compiler"
done

sha256sum "$overview" "$build/geotiff-metadata-overviews.gdal.json"
printf '%s\n' 'overview selection/oracle probe passed under DMD/LDC'
