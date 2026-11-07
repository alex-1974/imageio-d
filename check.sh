#!/bin/sh
set -eu

dub test --compiler=dmd --force
dub test --compiler=ldc2 --force
echo "imageio-d checks passed"
