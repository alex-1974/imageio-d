#!/bin/sh
set -eu

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/imageio-d.tar.gz"
git archive --format=tar.gz --prefix=imageio-d/ HEAD > "$archive"
tar -xzf "$archive" -C "$tmp"

test -s "$tmp/imageio-d/LICENSE"
test -s "$tmp/imageio-d/dub.sdl"
test -d "$tmp/imageio-d/source/imageio"

mkdir -p "$tmp/consumer/source"
cat > "$tmp/consumer/dub.sdl" <<EOF
name "imageio-d-clean-consumer"
targetType "executable"
dependency "imageio-d" path="../imageio-d"
sourcePaths "source"
EOF
cat > "$tmp/consumer/source/app.d" <<'EOF'
import imageio;
import transport : MemorySink;

void main()
{
    auto sink = new MemorySink();
    ubyte[3] pixel = [255, 0, 0];
    auto result = writePng(sink, PngWriteInfo(1, 1, 8, 2), pixel[], 3);
    assert(result.complete);
}
EOF
dub build --root="$tmp/consumer" --skip-registry=all
echo 'clean package archive consumer passed'
