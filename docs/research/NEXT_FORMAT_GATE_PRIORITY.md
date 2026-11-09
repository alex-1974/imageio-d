# Provisional next format-gate research queue

Status: 2026-10-28, research coordination only. This orders **experiments**,
not public format support, admission, milestones or a release. General image
editing, scientific editing and `dunia` are target profiles, not available
integration testbeds; the order must be revised when a real consumer supplies
files and workflows. Read and write remain independent capability cells.

## Current evidence behind the queue

The PNG read/write probe passes independent Pillow/ImageMagick/Python oracles
with DMD 2.111.0 and LDC 1.42.0 against `compression-d` remote `master`
`b0fc8d7`, including a fully linked DIP1000 consumer. The bounded baseline
JPEG read/write oracle and the uncompressed one-strip classic-TIFF write
oracle also passed both compilers on 2026-10-28. These checks reuse small,
generated corpora; they are not representative editor or satellite products.
The separate TIFF/BigTIFF read and Deflate range experiments have wider
technical coverage than the current writer. GeoTIFF keys and COG-specific
access remain bounded and consumer-qualified rather than universal. See `CAPABILITY_MATRIX.md`, `JPEG_GATE_PLAN.md`,
`PNG_EDITOR_GATE.md` and `FORMAT_GATE_STATUS.md` for exact subsets and gaps.

## Provisional order of the next bounded experiments

1. **JPEG editor read/write hardening.** This is the largest ordinary-image
   editor gap after the PNG consumer gate. Quality 1–100, 4:4:4/4:2:2/4:2:0
   write, restart intervals and explicit EXIF/ICC copy-or-discard now have
   bounded Pure-D oracles; an opaque metadata header scanner also exists.
   The bounded cross-MCU chroma defect is fixed with ≤3-level oracle deltas
   on 17×19/257×193 synthetic edge/gradient cases; a 1×19 case uses a
   different narrow-image interpolation policy than libjpeg-turbo. Broader
   image-quality evidence remains.
   Next experiment: integrated metadata loss policy and a representative
   real-world/security corpus,
   and entropy/DCT performance. Report per-channel error distributions, size,
   memory and latency against comparable reference configurations; the current
   1024×1024 run is materially slower/larger than Pillow/libjpeg. Keep CMYK,
   progressive and orientation *application* separately gated. Do not treat
   lossy decoded samples as byte-exact or hide RGB/YCbCr conversion.

2. **Scientific TIFF write plus technical GeoTIFF read evidence.** The writer
   currently emits one uncompressed little-endian chunky strip; the readers
   already probe native multiband samples, tiled/stripped access and BigTIFF
   ranges. Next experiment: a bounded multi-strip/tiled write slice with
   explicit native sample type, compression/predictor and metadata-loss
   policy, independently reopened by GDAL with exact native sample checks.
   In parallel, generate a GeoTIFF GeoKey metadata oracle (including malformed
   key directories and loss/retention) without binding CRS or NoData meaning
   inside imageio. Keep BigTIFF/GeoTIFF **write** as separate decisions until
   actual scientific-editor or `dunia` files require them. Record output
   capacity, partial-sink behavior, ROI/whole-image equivalence and copies.

3. **PNG editor completeness and regression protection.** Retain the now
   provider-backed, fully linked DIP1000 read/write oracle as a recurring
   research gate. Next incremental probes: packed/indexed *write* with an
   explicit representation choice, recognized ICC/EXIF transfer rules,
   chunked source/sink contracts and a broader malformed/size corpus. Adam7
   and APNG are separate gates. The small hash-chain speed/size snapshot is
   not a multi-fixture performance qualification.

4. **COG transport only after source and consumer evidence.** The BigTIFF
   range-window path is not a complete COG product. First measure local tiled
   GeoTIFF/overview byte ranges, requests and ROI amplification against an
   independent oracle; only then consider HTTP, source revision, cache and
   cancellation. Do not infer a `dunia` export format or remote-access need.

This is a queue for research effort, not a claim that JPEG must precede PNG
for product admission. The dependency order in `FORMAT_GATES.md` still applies
within TIFF/BigTIFF/GeoTIFF/COG. A real consumer read/edit/write path,
independent oracles, malformed-input safety, ownership/lifetime contracts and
representative DMD/LDC performance remain required before M5 can admit a
public imageio-d package or API.
