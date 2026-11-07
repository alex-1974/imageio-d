#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(mktemp -d)
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
python3 "$root/oracle.py" "$build"
for compiler in dmd ldc2; do
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" -of="$build/jpeg-test-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_driver.d"
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" -of="$build/metadata-read-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_metadata_read_probe.d"
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" -of="$build/native-pipeline-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_native_pipeline_probe.d"
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" -of="$build/header-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_stream_header.d" \
        "$root/source/jpeg_stream_header_probe.d"
    "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" \
        -of="$build/stream-gray-$compiler" \
        "$root/source/jpeg_research.d" "$root/source/jpeg_stream_header.d" \
        "$root/source/jpeg_stream_gray.d" \
        "$root/source/jpeg_stream_gray_probe.d"
    if [ "$(uname -s)" = Linux ]; then
        "$compiler" -w -dip1000 -boundscheck=on -I="$root/source" \
            -of="$build/header-pipe-$compiler" \
            "$root/source/jpeg_research.d" \
            "$root/source/jpeg_stream_header.d" \
            "$root/source/jpeg_stream_pipe_probe.d"
    fi
    for name in baseline-gray baseline-rgb baseline-rgb-422 baseline-rgb-420 metadata-rgb; do
        "$build/jpeg-test-$compiler" "$build/$name.jpg" "$build/$name.raw"
    done
    for name in progressive-rgb cmyk truncated bad-quant bad-huff adobe-rgb unsupported-440; do
        "$build/jpeg-test-$compiler" negative "$build/$name.jpg"
    done
    "$build/jpeg-test-$compiler" fuzz "$build/baseline-rgb.jpg"
    for name in baseline-gray baseline-rgb; do
        for quality in 1 30 75 95 100; do
            "$build/jpeg-test-$compiler" encode "$build/$name.raw" \
                "$build/$name-$compiler-q$quality.jpg" "$quality"
        done
    done
    for sampling in 422 420; do
        "$build/jpeg-test-$compiler" encode "$build/baseline-rgb.raw" \
            "$build/baseline-rgb-$compiler-$sampling.jpg" 95 "$sampling"
    done
    for name in baseline-gray baseline-rgb; do
        "$build/jpeg-test-$compiler" encode "$build/$name.raw" \
            "$build/$name-$compiler-rst1.jpg" 95 444 1
    done
    for sampling in 422 420; do
        "$build/jpeg-test-$compiler" encode "$build/baseline-rgb.raw" \
            "$build/baseline-rgb-$sampling-$compiler-rst1.jpg" 95 "$sampling" 1
    done
    "$build/jpeg-test-$compiler" metadata "$build/baseline-rgb.raw" \
        "$build/metadata.exif" "$build/metadata.icc" \
        "$build/baseline-rgb-$compiler-metadata.jpg"
    "$build/jpeg-test-$compiler" metadata "$build/baseline-rgb.raw" \
        "$build/metadata.exif" "$build/metadata-large.icc" \
        "$build/baseline-rgb-$compiler-metadata-large.jpg"
    "$build/header-$compiler" "$build/baseline-rgb.jpg" \
        "$build/metadata-rgb.jpg" \
        "$build/baseline-rgb-$compiler-metadata-large.jpg" \
        "$build/progressive-rgb.jpg"
    "$build/stream-gray-$compiler" "$build/baseline-gray.jpg" \
        "$build/baseline-gray-$compiler-q100.jpg" \
        "$build/baseline-gray-$compiler-rst1.jpg" \
        "$build/progressive-rgb.jpg"
    if [ "$(uname -s)" = Linux ]; then
        "$build/header-pipe-$compiler" "$build/baseline-rgb.jpg" \
            "$build/baseline-rgb-$compiler-metadata-large.jpg"
    fi
    "$build/jpeg-test-$compiler" inspectmeta "$build/metadata-rgb.jpg" \
        "$build/metadata.exif" "$build/metadata.icc"
    "$build/jpeg-test-$compiler" inspectmeta \
        "$build/baseline-rgb-$compiler-metadata-large.jpg" \
        "$build/metadata.exif" "$build/metadata-large.icc"
    "$build/jpeg-test-$compiler" inspectmeta \
        "$build/baseline-rgb-$compiler-metadata.jpg.drop.jpg" - -
    python3 "$root/verify_encoded.py" "$build" "$compiler"
    "$build/metadata-read-$compiler" "$build/baseline-rgb.jpg" - -
    "$build/metadata-read-$compiler" "$build/metadata-rgb.jpg" \
        "$build/metadata.exif" "$build/metadata.icc"
    "$build/metadata-read-$compiler" \
        "$build/baseline-rgb-$compiler-metadata-large.jpg" \
        "$build/metadata.exif" "$build/metadata-large.icc"
    "$build/metadata-read-$compiler" bad \
        "$build/bad-icc-sequence-$compiler.jpg"
    "$build/native-pipeline-$compiler" "$build/metadata-rgb.jpg" \
        "$build/metadata.exif" "$build/metadata.icc" \
        "$build/native-pipeline-$compiler.jpg"
    python3 "$root/verify_native_pipeline.py" \
        "$build/native-pipeline-$compiler.jpg" \
        "$build/metadata.exif" "$build/metadata.icc"
    "$build/native-pipeline-$compiler" \
        "$build/baseline-rgb-$compiler-metadata-large.jpg" \
        "$build/metadata.exif" "$build/metadata-large.icc" \
        "$build/native-pipeline-large-$compiler.jpg"
    python3 "$root/verify_native_pipeline.py" \
        "$build/native-pipeline-large-$compiler.jpg" \
        "$build/metadata.exif" "$build/metadata-large.icc"
    "$build/jpeg-test-$compiler" negative "$build/bad-restart-$compiler.jpg"
    "$build/jpeg-test-$compiler" inspectnegative \
        "$build/bad-icc-sequence-$compiler.jpg"
done
for name in baseline-gray baseline-rgb; do
    for quality in 1 30 75 95 100; do
        cmp "$build/$name-dmd-q$quality.jpg" "$build/$name-ldc2-q$quality.jpg"
    done
done
for sampling in 422 420; do
    cmp "$build/baseline-rgb-dmd-$sampling.jpg" \
        "$build/baseline-rgb-ldc2-$sampling.jpg"
done
for name in baseline-gray baseline-rgb baseline-rgb-422 baseline-rgb-420; do
    cmp "$build/$name-dmd-rst1.jpg" "$build/$name-ldc2-rst1.jpg"
done
for suffix in metadata.jpg metadata.jpg.drop.jpg metadata-large.jpg metadata-large.jpg.drop.jpg; do
    cmp "$build/baseline-rgb-dmd-$suffix" "$build/baseline-rgb-ldc2-$suffix"
done
for name in native-pipeline native-pipeline-large; do
    cmp "$build/$name-dmd.jpg" "$build/$name-ldc2.jpg"
    cmp "$build/$name-dmd.jpg.drop.jpg" \
        "$build/$name-ldc2.jpg.drop.jpg"
done
sh "$root/native.sh"
