#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
provider_root=${COMPRESSION_D_ROOT:-"$root/../../../../../compression-d"}
if [ ! -f "$provider_root/source/compression/encode.d" ]; then
    echo "compression-d source not found: $provider_root" >&2
    exit 1
fi
mkdir -p "$root/.build"
run_build=$(mktemp -d "$root/.build/png-bench.XXXXXX")
trap 'rm -rf -- "$run_build"' EXIT HUP INT TERM
cd "$root"
echo "compression-d commit: $(git -C "$provider_root" rev-parse HEAD)"
python3 oracle_fixtures.py prepare "$run_build" >/dev/null
for compiler in dmd ldc2; do
    if [ "$compiler" = dmd ]; then optimize=-O
    else optimize=-O3; fi
    "$compiler" -w -i -dip1000 "$optimize" -release -boundscheck=on \
        -I="$root/source" -I="$provider_root/source" \
        -of="$run_build/png-bench-$compiler" "$root/benchmark.d"
    for round in 1 2 3; do
        echo "compiler=$compiler round=$round"
        /usr/bin/time -f "$compiler peak_rss_kib=%M" \
            "$run_build/png-bench-$compiler" "$run_build/rgb8-128.png" 5
    done
done
