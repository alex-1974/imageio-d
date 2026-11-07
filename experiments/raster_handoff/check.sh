#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dub run --root="$root" --compiler=dmd
dub run --root="$root" --compiler=ldc2
