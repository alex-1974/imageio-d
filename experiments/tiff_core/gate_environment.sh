#!/bin/sh
set -eu

printf '%s\n' "format-gate environment"
for tool in dmd ldc2 gdal_translate magick python3; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-16s available (%s)\n' "$tool" "$(command -v "$tool")"
    else
        printf '  %-16s unavailable\n' "$tool"
    fi
done

printf '%s\n' "oracle capabilities"
if command -v gdal_translate >/dev/null 2>&1; then
    gdal_translate --formats 2>/dev/null | rg -q 'GTiff' && echo '  GeoTIFF/COG oracle: yes' || echo '  GeoTIFF/COG oracle: no'
else
    echo '  GeoTIFF/COG oracle: no'
fi
if command -v magick >/dev/null 2>&1; then
    magick -version | head -1
    echo '  PNG reference decoder: yes'
else
    echo '  PNG reference decoder: no'
fi
