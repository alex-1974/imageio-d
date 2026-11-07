#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
runs=${1:-3}

if [ ! -x "$build/benchmark-matrix-dmd" ] || [ ! -x "$build/benchmark-matrix-ldc" ]; then
    echo "run ./run.sh first" >&2
    exit 1
fi

case "$runs" in
    ''|*[!0-9]*) echo "runs must be a positive integer" >&2; exit 2 ;;
esac
[ "$runs" -gt 0 ] || exit 2

for compiler in dmd ldc; do
    binary="$build/benchmark-matrix-$compiler"
    echo "--- $compiler repeated matrix ($runs runs) ---"
    i=1
    while [ "$i" -le "$runs" ]; do
        /usr/bin/time -f "run=$i elapsed=%e sec max_rss=%M KB" "$binary" >/dev/null
        i=$((i + 1))
    done
done
