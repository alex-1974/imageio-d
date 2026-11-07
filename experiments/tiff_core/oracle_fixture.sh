#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixture="$root/.build/oracle-gray16.tif"
fixture8="$root/.build/oracle-gray8.tif"
fixtureRgb="$root/.build/oracle-rgb8.tif"
fixturePlanar="$root/.build/oracle-rgb8-planar.tif"
fixturePackBits="$root/.build/oracle-gray8-packbits.tif"
fixturePackBitsTile="$root/.build/oracle-gray8-packbits-tiled.tif"
fixtureTile="$root/.build/oracle-gray16-tiled.tif"
mkdir -p "$root/.build"

if ! command -v convert >/dev/null 2>&1 || ! command -v gdalinfo >/dev/null 2>&1; then
    echo "convert and gdalinfo are required" >&2
    exit 1
fi

# External fixture: ImageMagick creates the TIFF; GDAL reports its technical
# structure. The generated file is ignored and never becomes a source fixture.
convert -size 16x8 gradient: -depth 16 -define quantum:format=unsigned \
    -compress None "TIFF:$fixture"
convert -size 12x7 gradient: -depth 8 -compress None "TIFF:$fixture8"
gdal_translate -q -of GTiff -co COMPRESS=PACKBITS -co TILED=NO -co BLOCKYSIZE=2 \
    "$fixture8" "$fixturePackBits"
gdal_translate -q -of GTiff -co COMPRESS=PACKBITS -co TILED=YES \
    -co BLOCKXSIZE=16 -co BLOCKYSIZE=16 "$fixture8" "$fixturePackBitsTile"
convert -size 13x9 gradient:red-blue -depth 8 -compress None "TIFF:$fixtureRgb"
gdal_translate -q -of GTiff -co INTERLEAVE=BAND "$fixtureRgb" "$fixturePlanar"
# Request a tiled external fixture where the installed ImageMagick delegate
# supports it. Keep the fixture optional because TIFF tile writing is delegate
# and version dependent.
if convert -size 19x11 gradient: -depth 16 -define quantum:format=unsigned \
    -compress None -define tiff:tile-geometry=16x16 "TIFF:$fixtureTile" 2>/dev/null; then
    gdalinfo "$fixtureTile" | sed -n '1,14p'
else
    echo "optional tiled fixture unavailable"
fi
gdalinfo "$fixture"
gdalinfo "$fixture8"
gdalinfo "$fixturePackBits"
gdalinfo "$fixturePackBitsTile"
gdalinfo "$fixtureRgb"
gdalinfo "$fixturePlanar"

cd "$(dirname "$root")/.."
dmd -of="$root/.build/oracle-compare" -w -dip1000 \
    "$root/source/ifd_result.d" "$root/source/oracle_compare.d"
"$root/.build/oracle-compare"
"$root/.build/oracle-compare" "$fixture8" 12 7
"$root/.build/oracle-compare" "$fixtureRgb" 13 9 3
"$root/.build/oracle-compare" "$fixturePlanar" 13 9 3
if [ -f "$fixtureTile" ]; then
    "$root/.build/oracle-compare" "$fixtureTile" 19 11
fi

echo "oracle fixtures generated: $fixture $fixture8 $fixturePackBits $fixturePackBitsTile $fixtureRgb $fixturePlanar"
