# compression-d consumer experiment

This is an additive, research-only TIFF Deflate consumer. It introduces no
production `imageio-d` package/API and replaces none of the existing TIFF probes.
`dub.sdl` declares a real local path dependency on `compression-d`. Its path
assumes the existing workspace layout (`dlang/compression-d` beside
`dlang/d-geospatial-workspace/libs/imageio-d`); adjust that experiment-local path
if using another layout.

## What is integrated

`deflate_bridge.d` imports `compression.zlib.inflateZlib` and uses the existing
TIFF experiment's `Block` and `Layout` types. Compressed blocks are inflated
into caller-owned scratch with an absolute cap equal to the checked decoded
block size. The zlib trailer must verify, the decoded size must match exactly,
and the entire declared compressed block must be consumed before any pixels
from that block reach the destination.

The bounded metadata adapter handles classic TIFF, chunky/interleaved unsigned
8-/16-bit samples, strips or tiles, homogeneous sample depths, both byte orders,
Deflate compression IDs 8/32946, and Predictor 1/2. The independent generated
TIFF corpus uses ID 8. Padded edge tiles are inflated at their full logical size
and only visible pixels are copied. Predictor 2 is undone per row and band in
the file's sample byte order, modulo the sample width. Destination sample bytes
retain **file byte order**; no implicit normalization or color conversion occurs.

The separate `bigtiff_range_bridge.d` experiment accepts caller-read
`RangeWindow`s at absolute 64-bit file offsets. Its oracle reads the BigTIFF
header, IFD, external offset/count arrays and compressed strips/tiles as
independent file ranges, then passes each compressed window to the existing
Deflate block bridge. It checks both DMD and LDC against GDAL raw pixels for
strip/tile, RGB, 8-/16-bit and Predictor 2 fixtures. Rebased block windows
above 4 GiB, insufficient scratch, absent windows and strided destination
padding are also checked. No full-file image buffer or zlib runtime backend
is used by the D decoder.

Planar samples, float/signed samples, other predictors/codecs, general
metadata interpretation, a production BigTIFF/TIFF reader and automatic API
admission remain outside this experiment. The classic metadata adapter reuses `TagValue`, but
has a local borrowing byte cursor because the older Reader's methods do not
declare `scope` on `this`. It does not weaken the DIP1000 probe or modify that
older parser. `SampleFormat` defaults to unsigned; missing PlanarConfiguration
defaults to chunky. Deflate dictionaries are not silently accepted.

`decodeDeflateWindow` additionally accepts a checked pixel window and writes
only its intersecting tiles into a window-sized caller-owned destination. The
non-intersecting compressed blocks are not read or inflated. The `window` DUB
configuration exercises this path against the GeoTIFF metadata fixture and
checks native UInt16 values for a 7x6 window touching one of two tiles.

## Ownership, sizes and failures

All decoder operations are `@safe pure nothrow @nogc`. Input, destination,
scratch, descriptors and `InflateWorkspace` must not alias. Concurrent calls
need independent workspaces/scratch/destination storage. Sequential block and
image decodes reuse the same workspace; each zlib stream resets decoder state.
`requirements(spec)` checks geometry/products and reports output bytes,
maximum scratch bytes and block count. `Requirements.decoderBytes` is
`InflateWorkspace.sizeof`, separate from decoded-block scratch.

`decodeDeflateBlocks` validates ranges, overlap, layout and capacities before
emission. File-ordered ranges use linear overlap preflight; unordered ranges
retain a quadratic validation fallback. This fallback has not been qualified
for huge block tables. Caller-owned interleaved layout gaps remain untouched.
On a codec/size error, earlier successful blocks remain committed, the failing
block's destination remains untouched, and scratch is unspecified. Result
`blocksWritten` reports committed blocks and `codec` preserves codec categories.
Default `BridgeResult`/`Requirements` are invalid metadata, not success.
`decodeDeflateRanges` requires two caller-owned decoded-block buffers of
`requirements(spec).scratchBytes` each: inflate scratch and a staging block.
It preflights the supplied 64-bit block descriptors and windows before writing
pixels. File-ordered, index-matched block/window tables use linear validation;
unordered blocks or windows retain a quadratic fallback that is not yet
qualified for very large block tables. Both buffers and
the destination must not alias. A later failed block leaves earlier blocks
committed, while the failing block remains untouched.
`inspectTiff` initializes its `out` result; `readBlocks` may partially fill its
descriptor destination before failure. Failed plans must not be used.

## Running the gate

From the compression-d checkout:

```sh
bash scripts/check-consumers.sh
python3 scripts/bench-consumers.py --rounds 5 --iterations 20 --cpu 0
```

The checker accepts `IMAGEIO_D_ROOT` and `CONSUMER_PYTHON`; defaults target this
local checkout and `/usr/bin/python3` with GDAL's `osgeo` module. GDAL/zlib are
fixture generators/oracles only. Neither is a runtime backend of the D consumer.

The experiment can also build through DUB:

```sh
dub build --compiler=dmd
dub build --compiler=ldc2
.build/imageio-compression-consumer image.tif gdal-reference.raw
sh check-bigtiff-ranges.sh input.tif gdal-reference.raw
```

Evidence: eleven GDAL TIFF fixtures (8/16-bit, gray/RGB, both byte orders,
strips/tiles/edge padding/Predictor 2, including a 256x256 RGB16 workload),
exact-size/one-short workspace tests, checksum/truncation/size/layout/overflow
negatives, 500 bounded metadata mutations and two actual concurrent threads
(TIFF plus PNG consumer, 2,000 decodes each). Both DMD and LDC pass.

The local consumer depends on the pre-existing **uncommitted** TIFF research
modules `ifd_result.d`, `payload_decode.d` and `block_bridge.d`. Those files and
other active imageio-d work are preserved, not silently promoted into a commit.
The checker retains the exact needed consumer/context source in
`compression-d/.build/consumers/imageio-consumer-context.tar.gz`; benchmark JSON
records dependency hashes and both repository baselines. This local research
gate is not claimed to run from the public imageio-d `develop` checkout alone.

Provider-side evidence is in `compression-d/docs/CONSUMERS.md`. PNG scanline
experiments are a separate provider-side consumer, not a new imageio-d PNG API.
