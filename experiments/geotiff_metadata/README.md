# GeoTIFF metadata and COG research fixtures

This directory contains research-only fixture/oracle scripts for issues #4,
#7, #8 and #10. They do not add a public imageio-d API.

`sentinel_cog_compare.sh` reads metadata and a 32x24 native UInt16 window from
the Sentinel-2 B02 COG recorded in issue #3 through GDAL's `/vsicurl/` source.
It writes a JSON metadata oracle, a raw window oracle and hashes under
`.build/sentinel-cog/`. GDAL is an independent reference tool, not an
imageio-d runtime dependency. Use a pinned local copy as the argument when an
offline/reproducible run is required.
