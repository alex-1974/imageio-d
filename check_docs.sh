#!/bin/sh
set -eu

# DDOX renders the public Ddoc surface into docs/ and writes its intermediate
# JSON beside the package root. The generated site is a build artifact; the
# source Ddoc comments remain authoritative and are reviewed in Git.
dub build -b ddox

test -s docs/index.html
test -s docs/imageio.html
test -s docs/imageio/region.html
test -s docs/imageio/tiff.html
echo "imageio-d DDOX documentation passed"
