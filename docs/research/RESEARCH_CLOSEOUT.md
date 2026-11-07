# Research closeout — first Pure-D TIFF slice

Date: 2026-10-26

## Result

The first bounded, uncompressed TIFF vertical slice is accepted as a
research-quality capability. It is not admitted as a public package or stable
API.

## Evidence completed

- DMD 2.111.0 and LDC 1.42.0 compile and pass the same parser, ownership,
  strip, planar and tile oracles.
- External ImageMagick/GDAL fixtures cover 8-bit, RGB, native 16-bit,
  multi-strip planar and tiled edge cases.
- Real negative fixtures cover truncation, invalid order, invalid magic and
  invalid IFD offsets.
- 1024×1024 planar and tiled fixtures pass byte-for-byte against GDAL raw
  output.
- The corrected large benchmark uses an explicit non-inlineable consume. The
  local three-run baseline is recorded in `PERFORMANCE_BASELINE.md`.
- The consumer probe preserves source revision and explicit semantic bindings
  in the materialization key.

## Deliberate deferrals

- No public DUB package or production source tree.
- No compressed TIFF, BigTIFF, GeoTIFF keys, COG transport or PNG contract.
- No second physical host or independent compiler version is available in the
  current evidence set.
- The real `imagery-d` repository boundary still needs a consumer smoke test;
  the current probe is isolated but contract-shaped.
- Fuzzing/decompression-bomb limits and full metadata/NoData/mask policy remain
  separate gates.

## Recommendation

Proceed to a focused `imagery-d` consumer validation and API review. Do not
freeze module visibility, versioning or a DUB package until that review and a
second toolchain/host measurement are complete.
