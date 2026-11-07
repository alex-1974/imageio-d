#!/bin/sh
set -eu

# Research repositories may contain many untracked experiment sources, but a
# reviewable change set must not include compiler products or local fixtures.
bad=''
while IFS= read -r path; do
    if ! git check-ignore -q "$path"; then
        bad="$bad\n$path"
    fi
done <<EOF
$(find . -path './.git' -prune -o -type f \( \
    -name '*.o' -o -name '*.a' -o -name '*.so' -o -name '*.dylib' \
    -o -name '*.exe' -o -name 'imageio-d-test-library' \
    -o -name 'imageio-*-consumer' \) -print)
EOF
if [ -n "$bad" ]; then
    echo 'unignored generated build artefacts found:' >&2
    printf '%b\n' "$bad" >&2
    exit 1
fi

echo 'review scope is free of compiler products and experiment build directories'
