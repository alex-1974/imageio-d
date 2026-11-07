#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

dmd -of="$build/tiff-core-dmd" -w -dip1000 "$root/source/tiff_core.d"
"$build/tiff-core-dmd"

ldc2 -of="$build/tiff-core-ldc" -w -dip1000 "$root/source/tiff_core.d"
"$build/tiff-core-ldc"

dmd -of="$build/result-parser-dmd" -w -dip1000 "$root/source/result_parser.d"
"$build/result-parser-dmd"

ldc2 -of="$build/result-parser-ldc" -w -dip1000 "$root/source/result_parser.d"
"$build/result-parser-ldc"
echo "nogc result parser probe passed"

dmd -version=IFDProbe -of="$build/ifd-result-dmd" -w -dip1000 "$root/source/ifd_result.d"
"$build/ifd-result-dmd"
ldc2 -d-version=IFDProbe -of="$build/ifd-result-ldc" -w -dip1000 "$root/source/ifd_result.d"
"$build/ifd-result-ldc"
echo "nogc IFD result parser compile probe passed"

dmd -version=TagArrayProbe -of="$build/tag-arrays-dmd" -w -dip1000 "$root/source/tag_arrays.d"
"$build/tag-arrays-dmd"
ldc2 -d-version=TagArrayProbe -of="$build/tag-arrays-ldc" -w -dip1000 "$root/source/tag_arrays.d"
"$build/tag-arrays-ldc"
echo "nogc external tag-array probe passed"

dmd -version=PayloadProbe -of="$build/payload-decode-dmd" -w -dip1000 "$root/source/payload_decode.d"
"$build/payload-decode-dmd"
ldc2 -d-version=PayloadProbe -of="$build/payload-decode-ldc" -w -dip1000 "$root/source/payload_decode.d"
"$build/payload-decode-ldc"
echo "nogc uncompressed payload probe passed"

dmd -of="$build/strip-bridge-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/strip_bridge.d"
"$build/strip-bridge-dmd"
ldc2 -of="$build/strip-bridge-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/strip_bridge.d"
"$build/strip-bridge-ldc"
echo "nogc IFD-to-payload strip bridge probe passed"

dmd -version=BlockProbe -of="$build/block-bridge-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d"
"$build/block-bridge-dmd"
ldc2 -d-version=BlockProbe -of="$build/block-bridge-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d"
"$build/block-bridge-ldc"
echo "nogc multi-strip bridge probe passed"

dmd -version=BlockProbe -of="$build/block-tile-bridge-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d"
"$build/block-tile-bridge-dmd"
ldc2 -d-version=BlockProbe -of="$build/block-tile-bridge-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d"
"$build/block-tile-bridge-ldc"
echo "nogc tile bridge probe passed"

dmd -of="$build/workspace-boundary-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/packbits.d" "$root/source/compressed_strip_bridge.d" \
    "$root/source/compressed_tile_bridge.d" "$root/source/workspace_boundary_probe.d"
"$build/workspace-boundary-dmd"
ldc2 -of="$build/workspace-boundary-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/packbits.d" "$root/source/compressed_strip_bridge.d" \
    "$root/source/compressed_tile_bridge.d" "$root/source/workspace_boundary_probe.d"
"$build/workspace-boundary-ldc"
echo "nogc workspace boundary probe passed"

dmd -version=WorkspaceRequirementProbe -of="$build/workspace-requirements-dmd" -w -dip1000 \
    "$root/source/workspace_requirements.d"
"$build/workspace-requirements-dmd"
ldc2 -d-version=WorkspaceRequirementProbe -of="$build/workspace-requirements-ldc" -w -dip1000 \
    "$root/source/workspace_requirements.d"
"$build/workspace-requirements-ldc"
echo "nogc workspace requirement probe passed"

dmd -version=DeflateStoredProbe -of="$build/deflate-stored-dmd" -w -dip1000 \
    "$root/source/deflate_stored.d"
"$build/deflate-stored-dmd"
ldc2 -d-version=DeflateStoredProbe -of="$build/deflate-stored-ldc" -w -dip1000 \
    "$root/source/deflate_stored.d"
"$build/deflate-stored-ldc"
echo "nogc deflate stored-block probe passed"

dmd -version=DeflateHuffmanProbe -of="$build/deflate-huffman-dmd" -w -dip1000 \
    "$root/source/deflate_huffman.d"
"$build/deflate-huffman-dmd"
ldc2 -d-version=DeflateHuffmanProbe -of="$build/deflate-huffman-ldc" -w -dip1000 \
    "$root/source/deflate_huffman.d"
"$build/deflate-huffman-ldc"
echo "nogc deflate huffman-table probe passed"

dmd -version=DeflateTableProbe -of="$build/deflate-tables-dmd" -w -dip1000 \
    "$root/source/deflate_tables.d"
"$build/deflate-tables-dmd"
ldc2 -d-version=DeflateTableProbe -of="$build/deflate-tables-ldc" -w -dip1000 \
    "$root/source/deflate_tables.d"
"$build/deflate-tables-ldc"
echo "nogc deflate length-distance table probe passed"

dmd -version=DeflateCopyProbe -of="$build/deflate-copy-dmd" -w -dip1000 \
    "$root/source/deflate_copy.d"
"$build/deflate-copy-dmd"
ldc2 -d-version=DeflateCopyProbe -of="$build/deflate-copy-ldc" -w -dip1000 \
    "$root/source/deflate_copy.d"
"$build/deflate-copy-ldc"
echo "nogc deflate back-reference probe passed"

dmd -version=DeflateFixedProbe -of="$build/deflate-fixed-dmd" -w -dip1000 \
    "$root/source/deflate_huffman.d" "$root/source/deflate_fixed.d"
"$build/deflate-fixed-dmd"
ldc2 -d-version=DeflateFixedProbe -of="$build/deflate-fixed-ldc" -w -dip1000 \
    "$root/source/deflate_huffman.d" "$root/source/deflate_fixed.d"
"$build/deflate-fixed-ldc"
echo "nogc deflate fixed-table integration probe passed"

dmd -O -release -of="$build/tile-benchmark-dmd" -w -dip1000 \
    -I="$root/source" "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tile_benchmark.d" "$root/source/tuning.d"
"$build/tile-benchmark-dmd"
ldc2 -O3 -release -of="$build/tile-benchmark-ldc" -w -dip1000 \
    -I="$root/source" "$root/source/payload_decode.d" "$root/source/block_bridge.d" \
    "$root/source/tile_benchmark.d" "$root/source/tuning.d"
"$build/tile-benchmark-ldc"

dmd -of="$build/sample-oracle-dmd" -w -dip1000 "$root/source/sample_oracle.d"
"$build/sample-oracle-dmd"
ldc2 -of="$build/sample-oracle-ldc" -w -dip1000 "$root/source/sample_oracle.d"
"$build/sample-oracle-ldc"
echo "nogc sample endian oracle probe passed"

dmd -of="$build/float-oracle-dmd" -w -dip1000 "$root/source/float_oracle.d"
"$build/float-oracle-dmd"
ldc2 -of="$build/float-oracle-ldc" -w -dip1000 "$root/source/float_oracle.d"
"$build/float-oracle-ldc"
echo "nogc float bit oracle probe passed"

dmd -of="$build/benchmark-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/benchmark.d"
"$build/benchmark-dmd"
ldc2 -of="$build/benchmark-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/benchmark.d"
"$build/benchmark-ldc"

dmd -O -release -of="$build/benchmark-matrix-dmd" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/benchmark_matrix.d"
"$build/benchmark-matrix-dmd"
ldc2 -O3 -release -of="$build/benchmark-matrix-ldc" -w -dip1000 \
    "$root/source/payload_decode.d" "$root/source/benchmark_matrix.d"
"$build/benchmark-matrix-ldc"
