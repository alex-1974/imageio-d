#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
provider_root=${COMPRESSION_D_ROOT:-"$root/../../../../../compression-d"}
if [ ! -f "$provider_root/source/compression/encode.d" ]; then
    echo "compression-d source not found: $provider_root" >&2
    exit 1
fi
mkdir -p "$root/.build"
run_build=$(mktemp -d "$root/.build/png-oracle.XXXXXX")
trap 'rm -rf -- "$run_build"' EXIT HUP INT TERM
cd "$root"
echo "compression-d commit: $(git -C "$provider_root" rev-parse HEAD)"
python3 -c 'import PIL; print("Pillow", PIL.__version__)'
convert -version | head -1
python3 oracle_fixtures.py prepare "$run_build"
for compiler in dmd ldc2; do
    if [ -z "${COMPRESSION_D_ROOT+x}" ]; then
        # The experiment-local DUB package must remain buildable with its
        # declared local path dependency, not just by direct source import.
        dub build --compiler="$compiler" --quiet
    fi
    # Compile and link the imageio consumer together with the selected
    # provider under DIP1000, then use that exact binary for all oracles.
    "$compiler" -w -i -dip1000 -I="$root/source" \
        -I="$provider_root/source" \
        -of="$run_build/png-oracle-$compiler" \
        "$root/source/png_oracle.d" "$root/source/png_api_probe.d"
    for raw in "$run_build"/*.raw; do
        name=$(basename "$raw" .raw)
        "$run_build/png-oracle-$compiler" \
            "$run_build/$name.png" "$raw" "$run_build/$name-$compiler.png"
    done
    for native in "$run_build"/*.native; do
        name=$(basename "$native" .native)
        "$run_build/png-oracle-$compiler" read-only \
            "$run_build/$name.png" "$native"
    done
    "$run_build/png-oracle-$compiler" negative "$run_build"
    python3 oracle_fixtures.py verify "$run_build" "$compiler"
done
echo 'Pure-D PNG research read/write oracle passed under DMD/LDC'
