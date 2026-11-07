#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

"$root/oracle_fixture.sh" >/dev/null
fixture="$build/geotiff-metadata.tif"

dmd -w -dip1000 -version=LocalRangeProbe \
    -of="$build/local-range-dmd" "$root/local_range_probe.d"
"$build/local-range-dmd" "$fixture"

ldc2 -w -dip1000 -d-version=LocalRangeProbe \
    -of="$build/local-range-ldc" "$root/local_range_probe.d"
"$build/local-range-ldc" "$fixture"

echo 'local range source probe passed under DMD/LDC'
