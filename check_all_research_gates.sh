#!/bin/sh
set -eu

run_gate()
{
    name=$1
    script=$2
    echo "=== $name ==="
    sh "$script"
}

run_gate 'package DMD/LDC' ./check.sh
run_gate 'clean package archive consumer' ./check_package_consumer.sh
run_gate 'review scope' ./check_review_scope.sh
run_gate 'GeoTIFF inspection' experiments/geotiff_metadata/check_inspection.sh
run_gate 'GeoTIFF range decode' experiments/geotiff_metadata/check_range_decode.sh
run_gate 'GeoTIFF overview planning' experiments/geotiff_metadata/check_overview_window_plan.sh
run_gate 'COG orchestration' experiments/geotiff_metadata/check_cog_gate.sh
run_gate 'JPEG gate' experiments/jpeg_gate/check.sh
run_gate 'PNG read/write gate' experiments/png_rw/check.sh
run_gate 'raster handoff' experiments/raster_handoff/check.sh
run_gate 'public TIFF consumer' experiments/public_tiff_consumer/check.sh
run_gate 'public TIFF write consumer' experiments/public_tiff_write_consumer/check.sh

echo 'all local research gates passed'
