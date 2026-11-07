#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"

dmd -of="$build/api-fit-dmd" -w -dip1000 "$root/source/api_fit.d"
"$build/api-fit-dmd"

ldc2 -of="$build/api-fit-ldc" -w -dip1000 "$root/source/api_fit.d"
"$build/api-fit-ldc"

for compiler in dmd ldc2; do
    "$compiler" -c -o- -w -dip1000 "$root/source/destination_layout.d" \
        -of="$build/destination-$compiler.o"
    "$compiler" -c -o- -w -dip1000 "$root/source/metadata_boundary.d" \
        -of="$build/metadata-$compiler.o"
done
echo "caller-owned destination/layout probe passed"
echo "technical/semantic metadata boundary probe passed"

for compiler in dmd ldc2; do
    "$compiler" -c -o- -w -dip1000 "$root/source/write_fit.d" \
        -of="$build/write-$compiler.o"
done
echo "intuitive write-side vocabulary probe passed"

for compiler in dmd ldc2; do
    "$compiler" -of="$build/errors-$compiler" -w -dip1000 \
        "$root/source/error_contract.d"
    "$build/errors-$compiler"
done
echo "structured error/partial-write contract probe passed"

dmd -of="$build/imagery-consumer-dmd" -w -dip1000 "$root/source/imagery_consumer.d"
"$build/imagery-consumer-dmd"
ldc2 -of="$build/imagery-consumer-ldc" -w -dip1000 "$root/source/imagery_consumer.d"
"$build/imagery-consumer-ldc"
echo "imagery consumer materialization probe passed"

for compiler in dmd ldc2; do
    if "$compiler" -c -o- -w -dip1000 "$root/source/positive_borrow_return.d" \
        -of="$build/positive-$compiler.o"; then
        :
    else
        echo "$compiler positive lifetime probe failed" >&2
        exit 1
    fi

    if "$compiler" -c -o- -w -dip1000 "$root/source/negative_borrow_escape.d" \
        -of="$build/negative-$compiler.o" >/dev/null 2>&1; then
        echo "$compiler negative lifetime probe unexpectedly compiled" >&2
        exit 1
    else
        echo "$compiler negative lifetime probe rejected as expected"
    fi
done
