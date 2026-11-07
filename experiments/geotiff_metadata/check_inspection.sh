#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

"$root/oracle_fixture.sh" >/dev/null
fixture="$build/geotiff-metadata.tif"
source="$root/../tiff_core/source"

dmd -w -dip1000 -version=GeoTiffInspectionProbe \
    -of="$build/inspection-dmd" \
    "$source/ifd_result.d" "$source/geotiff_inspection.d"
"$build/inspection-dmd" "$fixture"

ldc2 -w -dip1000 -d-version=GeoTiffInspectionProbe \
    -of="$build/inspection-ldc" \
    "$source/ifd_result.d" "$source/geotiff_inspection.d"
"$build/inspection-ldc" "$fixture"

echo 'GeoTIFF technical inspection probe passed under DMD/LDC'
