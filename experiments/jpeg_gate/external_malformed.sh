#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
revision=ac980c295cb62c925d03d47990925d49c36eef18
base="https://raw.githubusercontent.com/imazen/codec-corpus/$revision/jpeg-conformance/invalid"
for name in empty.jpg missing-sof.jpg missing-sos.jpg invalid-dimensions.jpg \
    null_height.jpg max_size.jpg derive-huffman-codes-overflow.jpg \
    dc-predictor-overflow.jpg subtract-with-overflow.jpg \
    invalid-prediction-shift.jpg; do
    curl -fsSL "$base/$name" -o "$build/$name"
done
(
    cd "$build"
    printf '%s\n' \
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  empty.jpg' \
        'e9ef86bdf43856f5b290bf08886b56470c716665acf610b0a248175f56b29188  missing-sof.jpg' \
        'a355e29fd9194625b0cb1286d759d70cc49ee8b14eae48a9da473094f86bba67  missing-sos.jpg' \
        '56e9e75287d4baedc54a0b85b967bcb708965f9583380f41d9e3f6fb97ac4ce8  invalid-dimensions.jpg' \
        'ecf8b7f1620d5058856ad1f2dbb82c99b0582b2f0a6a2364ef40071386f181ec  null_height.jpg' \
        '4d88e9b396f8d903663428f480bd85278edfad16c92fb48f6dee19d7f5798f28  max_size.jpg' \
        '22d1f5a1d4338ac29982f8779bb97dbb9c855e578ecc18a57d35b3172fd8e329  derive-huffman-codes-overflow.jpg' \
        '94f3270e02c0bb6816cf81f35a3398821fce968ee7e65a8b700c71d4bac43d49  dc-predictor-overflow.jpg' \
        '22822b8d6a4bf2b70b6964972a6e9001329d63da35558c1a0923e3cafc839385  subtract-with-overflow.jpg' \
        '6b2d0e374b216ea8d2a4dc95745164871d5c83d7cfaa4e40e79c22e683b195db  invalid-prediction-shift.jpg' |
        sha256sum -c -
)
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" \
        -of="$build/external-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_external_corpus.d"
    "$build/external-$compiler" "$build/empty.jpg" "$build/missing-sof.jpg" \
        "$build/missing-sos.jpg" "$build/invalid-dimensions.jpg" \
        "$build/null_height.jpg" "$build/max_size.jpg" \
        "$build/derive-huffman-codes-overflow.jpg" \
        "$build/dc-predictor-overflow.jpg" \
        "$build/subtract-with-overflow.jpg" \
        "$build/invalid-prediction-shift.jpg"
done
