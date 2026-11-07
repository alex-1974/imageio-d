#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"

if [ ! -x "$build/benchmark-matrix-dmd" ] || [ ! -x "$build/benchmark-matrix-ldc" ]; then
    echo "run ./run.sh first" >&2
    exit 1
fi

for binary in "$build/benchmark-matrix-dmd" "$build/benchmark-matrix-ldc"; do
    echo "--- $(basename "$binary") ---"
    /usr/bin/time -f 'elapsed=%e sec max_rss=%M KB' "$binary" >/dev/null
done
