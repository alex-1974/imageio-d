# Multi-component TIFF inspection and materialization regression

Date: 2026-11-22. Fix based on the affected v0.1.1 tag; no new codec or public
API admission. This is a correction to the tagged bounded read contract, despite
the historical research-only wording retained in AGENTS/roadmap documents.
The original repository worktree and release refs remain unchanged.

## Trigger

imagery-d #174/#175 qualification produced an ordinary GDAL RGB GeoTIFF with
three SHORT BitsPerSample entries `[8,8,8]`. Inspection left the uniform depth
at zero, and decodeInfo's initial layout gate rejected it before the later
array-reading block could execute. Both pixel decoding and cost planning failed
to expose the already-supported uniform component representation correctly.

Resolve matching 2..4-component uniform SHORT arrays while inspecting the IFD.
This makes `bitsPerSample`, `plan.decodedBytes` and `decoded.sourceInfo` agree.
Mixed depths and mismatched counts remain unsupported; truncated metadata
fails inspection. No source color, alpha, range or CRS interpretation is added.
Only a bounded maximum of four depth values is read for this correction.

The same path requires correct inline integer-array handling. Classic TIFF
has four inline bytes, BigTIFF eight; extraction must respect both element
width and file byte order. Pass the known header format to the private integer
reader and handle inline SHORT/LONG/LONG8 values consistently. External arrays
retain their bounded range-read path, with checked allocation multiplication.

End-to-end imagery qualification then exposed a second issue: multi-component
TIFF regions reported one component byte-width as their interleaved X sample
stride. Report the complete pixel stride for both strip and tile decoders.
Clarify that `ImageRegionInfo.sampleStrideBytes` is the distance to the next X
sample of the same component; channel offset and pixel step are different.

## Retained qualification

- A permanent unit corpus covers 24 classic/BigTIFF, little/big endian,
  2/3/4-component and u8/u16 layouts. It checks inspection, ROI samples,
  decoded-byte planning, source facts and row/sample strides. Mixed depths,
  wrong count and truncated depth data remain explicit failures.
- `experiments/multichannel_tiff_regression/check.py` uses GDAL to produce 48
  strip/tile files across the same header/byte-order/component/depth axes.
  GDAL independently reads them into compact BIP ENVI numeric arrays. This
  avoids guessing how GDAL scales an added mask/alpha channel during UInt16
  conversion. The three source color bands also match their analytic map.
- The public DUB consumer checks four whole/ROI windows per file, including
  a tile seam and last pixel: 192 cases and 49,824 exact scalar samples.
  Planned/actual decoded bytes, nonzero encoded ranges and layout metadata agree.
- imagery-d's independent materialization consumer additionally verifies the
  actual RGB GeoTIFF -> owned raster -> CRS/ROI/NoData handoff. Its isolated
  path override does not alter global DUB registrations or released packages.

Reproduce from this checkout with installed GDAL CLI tools:

```
dub test --compiler=dmd-2.111.0
dub test --compiler=ldc-1.43.0
dub build --root=experiments/multichannel_tiff_regression --compiler=ldc-1.43.0 --build=release
python3 experiments/multichannel_tiff_regression/check.py experiments/multichannel_tiff_regression/multichannel-tiff-regression
```

This does not publish a version or rewrite the v0.1.1 tag. Consumers using the
released package retain its original behavior until the fix is integrated and
qualified as a new release. The repository's existing broader format/research
gates remain independent of this focused regression job.
