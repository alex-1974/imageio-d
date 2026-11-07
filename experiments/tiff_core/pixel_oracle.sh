#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
"$root/oracle_fixture.sh" >/dev/null
fixture="$build/oracle-rgb8.tif"
raw="$build/oracle-rgb8.raw"
grayFixture="$build/oracle-gray8.tif"
grayRaw="$build/oracle-gray8.raw"
gray16Fixture="$build/oracle-gray16.tif"
gray16Raw="$build/oracle-gray16.raw"
tileFixture="$build/oracle-gray16-tiled.tif"
tileRaw="$build/oracle-gray16-tiled.raw"

if ! command -v gdal_translate >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
    echo "gdal_translate and sha256sum are required" >&2
    exit 1
fi

if [ ! -f "$fixture" ]; then
    "$root/oracle_fixture.sh" >/dev/null
fi

gdal_translate -q -of ENVI -ot Byte "$fixture" "$build/oracle-rgb8"
mv "$build/oracle-rgb8" "$raw"
gdal_translate -q -of ENVI -ot Byte "$grayFixture" "$build/oracle-gray8"
mv "$build/oracle-gray8" "$grayRaw"
gdal_translate -q -of ENVI -ot UInt16 "$gray16Fixture" "$build/oracle-gray16"
mv "$build/oracle-gray16" "$gray16Raw"
gdal_translate -q -of ENVI -ot UInt16 "$tileFixture" "$build/oracle-gray16-tiled"
mv "$build/oracle-gray16-tiled" "$tileRaw"

dmd -of="$build/raw-checksum" -w -dip1000 "$root/source/raw_checksum.d"
pure=$($build/raw-checksum "$raw")
sha=$(sha256sum "$raw")
echo "GDAL RGB raw oracle: $pure"
echo "external SHA-256: ${sha%% *}"

bytes=$(wc -c < "$raw")
[ "$bytes" -eq 351 ]
echo "pixel oracle passed: 13x9x3 byte stream"

dmd -of="$build/tiff-strip-oracle" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/payload_decode.d" \
    "$root/source/block_bridge.d" "$root/source/tiff_strip_oracle.d"
"$build/tiff-strip-oracle" "$grayFixture" "$grayRaw"
"$build/tiff-strip-oracle" "$fixture" "$raw"
"$build/tiff-strip-oracle" "$gray16Fixture" "$gray16Raw" 2

ldc2 -of="$build/tiff-strip-oracle-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/payload_decode.d" \
    "$root/source/block_bridge.d" "$root/source/tiff_strip_oracle.d"
"$build/tiff-strip-oracle-ldc" "$grayFixture" "$grayRaw"
"$build/tiff-strip-oracle-ldc" "$fixture" "$raw"
"$build/tiff-strip-oracle-ldc" "$gray16Fixture" "$gray16Raw" 2

dmd -of="$build/tiff-planar-oracle" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_planar_oracle.d"
"$build/tiff-planar-oracle" "$build/oracle-rgb8-planar.tif" "$raw" 13 9

dmd -of="$build/tiff-tile-oracle" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_tile_oracle.d"
"$build/tiff-tile-oracle" "$tileFixture" "$tileRaw" 19 11 16 16

ldc2 -of="$build/tiff-planar-oracle-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_planar_oracle.d"
"$build/tiff-planar-oracle-ldc" "$build/oracle-rgb8-planar.tif" "$raw" 13 9

ldc2 -of="$build/tiff-tile-oracle-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tiff_tile_oracle.d"
"$build/tiff-tile-oracle-ldc" "$tileFixture" "$tileRaw" 19 11 16 16

gdal_translate -q -of ENVI -ot Byte "$build/oracle-gray8-packbits.tif" "$build/oracle-gray8-packbits"
mv "$build/oracle-gray8-packbits" "$build/oracle-gray8-packbits.raw"
dmd -of="$build/packbits-fixture-oracle" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" "$root/source/packbits.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/compressed_strip_bridge.d" "$root/source/packbits_fixture_oracle.d"
"$build/packbits-fixture-oracle" "$build/oracle-gray8-packbits.tif" \
    "$build/oracle-gray8-packbits.raw"
ldc2 -of="$build/packbits-fixture-oracle-ldc" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" "$root/source/packbits.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/compressed_strip_bridge.d" "$root/source/packbits_fixture_oracle.d"
"$build/packbits-fixture-oracle-ldc" "$build/oracle-gray8-packbits.tif" \
    "$build/oracle-gray8-packbits.raw"
dmd -of="$build/packbits-tile-oracle" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" "$root/source/packbits.d" \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/compressed_tile_bridge.d" "$root/source/packbits_tile_oracle.d"
"$build/packbits-tile-oracle" "$build/oracle-gray8-packbits-tiled.tif" \
    "$build/oracle-gray8.raw"

dmd -of="$build/fixture-negative" -w -dip1000 -I="$root/source" \
    "$root/source/ifd_result.d" "$root/source/tag_arrays.d" \
    "$root/source/fixture_negative.d"
"$build/fixture-negative" "$fixture" "$build/oracle-rgb8-planar.tif" \
    "$tileFixture"
echo "external fixture negative corpus passed"


