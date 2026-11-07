# Pure-D TIFF core experiment

Research-only prototype for ADR 0003. It parses classic TIFF headers and IFD
entries for a small set of technical tags. It does not decode pixels, support
compression, implement GeoTIFF keys or define production API.

`result_parser.d` is the preferred direction for the performance-critical
path: structured errors, `@safe`, `@nogc`, `nothrow` and no exception
allocation.

`tag_arrays.d` now covers caller-owned external LONG and SHORT arrays. The
SHORT path is needed for multi-band `BitsPerSample`; full IFD integration and
pixel differential fixtures remain separate admission work.

The IFD result records whether `BitsPerSample` is inline or an external SHORT
array (`bitsPerSampleCount` and `bitsPerSampleOffset`). It does not allocate or
silently collapse a multi-band array into one scalar.

`oracle_fixture.sh` also generates an external RGB fixture and checks its
three-band technical shape against GDAL.

`pixel_oracle.sh` exports that fixture through GDAL to a deterministic raw
13×9×3 byte stream and records both a Pure-D checksum and an external SHA-256.
This is a fixture/pixel-stream oracle; it is not yet a differential test of
the Pure-D TIFF payload decoder.

The same script now performs complete strip, planar and tiled comparisons. The
tiled case uses a 19×11 image with 16×16 tiles, so the final tile is an edge
tile; the decoder writes visible pixels directly into the caller-owned output
and ignores source padding.

Run `./run.sh`.
