#!/bin/sh
set -eu
cd "$(dirname "$0")"
fixture="../geotiff_metadata/.build/geotiff-metadata.tif"
../geotiff_metadata/oracle_fixture.sh >/dev/null
truncated="../geotiff_metadata/.build/geotiff-metadata.truncated-public.tif"
head -c 500 "$fixture" > "$truncated"
../geotiff_metadata/check_overviews.sh >/dev/null
overview="../geotiff_metadata/.build/geotiff-metadata-overviews.tif"
packbits="../geotiff_metadata/.build/geotiff-packbits.tif"
lzw="../geotiff_metadata/.build/geotiff-lzw.tif"
bigtiff="../geotiff_metadata/.build/geotiff-bigtiff.tif"
jpeg="../geotiff_metadata/.build/geotiff-jpeg.tif"
for compiler in dmd ldc2; do
    dub run --compiler="$compiler" --force -- "$fixture"
    dub run --compiler="$compiler" --force -- "$overview"
    dub run --compiler="$compiler" --force -- "$packbits"
    dub run --compiler="$compiler" --force -- "$lzw"
    dub run --compiler="$compiler" --force -- "$bigtiff"
    dub run --compiler="$compiler" --force -- "$jpeg"
    if dub run --compiler="$compiler" --force -- "$truncated"; then
        echo "truncated TIFF unexpectedly succeeded" >&2
        exit 1
    fi
done
echo "public TIFF consumer passed under DMD/LDC"
