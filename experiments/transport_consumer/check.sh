#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixture="$root/../geotiff_metadata/.build/geotiff-metadata.tif"
"$root/../geotiff_metadata/oracle_fixture.sh" >/dev/null
for compiler in dmd ldc2; do
    dub run --root="$root" --compiler="$compiler" -- "$fixture"
done
url=${SENTINEL_COG_URL:-https://sentinel-cogs.s3.amazonaws.com/sentinel-s2-l2a-cogs/12/R/UU/2024/4/S2A_12RUU_20240421_0_L2A/B02.tif}
for compiler in dmd ldc2; do
    dub run --root="$root" --compiler="$compiler" --config=http -- "$url"
done
for compiler in dmd ldc2; do
    dub run --root="$root" --compiler="$compiler" --config=range -- \
        "$fixture"
done
