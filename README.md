# imageio-d — Image I/O research

**Status: research only — no production package/API admitted.**

Research whether an independent Pure-D image I/O library provides a
coherent read/write boundary between encoded image formats/transport and
already-decoded numeric raster/image processing. Investigate existing D
libraries first; implement only when a consumer-driven experiment shows a
capability gap and the repository's admission gate is satisfied.

The current branch contains an unreleased, research-backed DUB package and
public API probes. The qualified research slice is classic TIFF inspection
and bounded ROI decoding through `transport-d`, including UInt8/UInt16,
interleaved strips/tiles, zlib Deflate, PackBits, LZW, BigTIFF, grayscale
JPEG-in-TIFF and Predictor 2. It is not yet a
supported release or a complete TIFF implementation.

The current consumer flow is:

```d
auto detected = detectFormat(source);
auto levels = inspectLevels(source);
auto level = selectLevel(levels.levels, width, height);
auto plan = planRegion(source, x, y, width, height);
auto pixels = decodeRegion(source, x, y, width, height);
```

Format detection uses the content signature. File extensions and HTTP content
types are hints only. The decoder returns technical `ImageRegion` data; it
does not assign RGB(A), NoData, radiometric or CRS semantics.

## Dependency boundary

The imageio package depends on transport and compression, but not on
`raster-d` or `imagery-d`:

```text
containers-d → transport-d → imageio-d
                              ↓
                         ImageRegion
                              ↓
                  imagery/raster adapters
```

`imagery-d` may materialize an `ImageRegion` into a `raster-d` lease. That is
an imagery-side integration choice and is not part of imageio's core
dependency graph.

## Motivation

`imagery-d` must operate on image semantics independently of the original
file format, codec, or origin. `raster-d` owns generic retained raster memory,
views, strides, ROI and numerical raster processing. `color-d` owns colour
mathematics. None should silently become a JPEG, PNG, TIFF, EXR or HTTP
implementation. This repository evaluates the missing format/interchange
boundary without duplicating those libraries.

## Candidate domain (not accepted API)

- Encoded resource discovery / format identification and safe decoder selection.
- Source access through local files, caller-supplied bytes/streams and
  eventually ranged remote transport when justified.
- Explicit header and representation metadata discovery; no hidden assumption
  that four bands means RGBA or ushort means normalized sRGB.
- Decode native region/window when the backend permits it; surface when
  full decode is unavoidable rather than promising arbitrary cheap ROI.
- Explicit destination/storage integration with public `raster-d` ownership
  and leases; compare direct adoption, caller-owned buffers and copying.
- Encode/write is a first-class product requirement. Each format and direction
  needs a separately qualified subset, explicit representation, failure,
  partial-write and metadata-loss policies.
- Preserve source metadata and provenance faithfully; any mapping into
  image-channel, NoData, alpha, spectral or presentation semantics is explicit
  and governed by the accepted `imagery-d` M1/M2 contracts.
- Investigate metadata and color-profile handling but do not implement a
  second colour-management engine.

## Explicit non-goals

- No new pixel/raster storage class, ROI engine, generic kernel or raster cache.
- No image processing, display mapping or implicit colour conversions.
- No competing TIFF/JPEG/PNG codec implementations without evidence.
- No general source scheduler/cache/DAG merely to support one reader.
- No compulsory `imagery-d` dependency. Generated rasters and image-processing
  consumers without files must remain independent of image I/O.

## Candidate relationships

```text
application/adapter ----> imageio-d (candidate)
         |                    |
         v                    v
     imagery-d ----------> raster-d
         |
         v
      color-d
```

`imageio-d` and `imagery-d` remain decoupled at the implementation level.
`imageio-d` returns the neutral `ImageRegion` contract; `imagery-d` may depend
on imageio-d for convenient ingestion and may materialize that region into
`raster-d`. `imageio-d` itself does not depend on either imagery-d or raster-d.

GDAL is test-only. It is used by the reproducible fixture/oracle scripts and
the optional public integration CI job to create and validate GeoTIFF and
overview fixtures. It is not an imageio-d dependency, runtime backend or
public API requirement.

## Sources / current prior evidence

- D Gamut: https://codemirror.dlang.org/packages/gamut
- D imageformats: https://codemirror.dlang.org/packages/imageformats
- OpenImageIO: https://openimageio.readthedocs.io/
- libvips: https://www.libvips.org/
- GDAL raster data model: https://gdal.org/en/stable/user/raster_data_model.html
- GeoTIFF: https://www.ogc.org/standards/geotiff/
- imagery-d M1: https://github.com/alex-1974/imagery-d/blob/develop/docs/adr/0002-image-semantic-core.md
- imagery-d M2: https://github.com/alex-1974/imagery-d/blob/develop/docs/adr/0003-source-cache-pipeline-architecture.md
- raster-d: https://github.com/alex-1974/raster-d

## Development and activation policy

Current `develop` is research coordination, **not** a released library.
The repository now contains an unreleased `dub.sdl`, `source/` tree and
package-root module for reproducible research consumers. These files do not
constitute a supported release baseline or a frozen public API. Follow
`AGENTS.md`, `ROADMAP.md` and current workspace engineering rules.

## Product hypothesis

The project investigates a **D-native** image-I/O library from the beginning.
Existing D and native libraries are research references and correctness/
performance comparators, not runtime backends or wrappers for the eventual
library. A production package is justified only if its API and contracts make
technical image interchange substantially more natural for D consumers than
direct use of an existing library.

The intended differentiator is a D-idiomatic, format-neutral boundary between
encoded sources and `raster-d`/`imagery-d` consumers:

- native sample and technical-metadata fidelity;
- explicit source inspection, region reads, layouts and conversions;
- visible ownership, borrowing, lifetimes and bounded residency;
- no implicit RGBA, colour, radiometric or NoData interpretation;
- direct composition with `raster-d` storage, views and leases;
- Pure-D builds with DMD and LDC, subject to measured correctness and
  performance evidence.

The API must feel like a natural D library. Names, modules, structs, slices,
`scope`, `ref`, `@safe`, `@nogc`, error handling and ownership vocabulary are
first-class research subjects, not post-hoc polish. See the accepted research
direction in `docs/adr/0001-pure-d-native-direction.md` and the API questions
in `docs/adr/0002-d-idiomatic-api-contract.md`.

## Intended consumers and scope

General image-editing software, scientific image editing, and `dunia`
satellite-image analysis are intended consumers, not available integration
testbeds today. Editors need both reading and saving; `dunia` needs input,
while its export needs remain unknown. The bounded TIFF reader work is an
initial research slice, not the intended format or direction limit. JPEG and PNG
read/write, TIFF write, and any further common formats require separate
consumer-backed capability and correctness gates before support can be
claimed. `dunia` is not yet ready; its exact input/output products and workflow
must not be inferred. Research may use independent oracles and explicitly
labeled consumer-shaped probes, but real consumer validation remains open.

`imageio-d` owns encoded formats and technical representation. `raster-d`
owns storage/views/ROI; `color-d` owns colour mathematics; `imagery-d` owns
image meaning and processing. Applications or thin adapters select source,
semantic binding and export policy. Generated imagery must not require I/O.
See `docs/adr/0006-image-io-for-imagery.md` and
`docs/research/CONSUMER_READ_WRITE.md`.
Current per-format research evidence and explicit gaps are in
`docs/research/CAPABILITY_MATRIX.md`; the first PNG read/write experiment is
under `experiments/png_rw/`. It now includes row-bounded IDAT decoding,
technical indexed/packed reads and an explicit fast stored-row write option;
the adaptive-filter, provider-backed fast-Deflate and conservative metadata-transfer
probes add evidence, but speed/size qualification and semantic metadata
trade-offs are not resolved. A separate
uncompressed classic-TIFF writer oracle is under `experiments/tiff_write/`,
and `experiments/jpeg_gate/` now includes a bounded Pure-D baseline JPEG
read/write experiment with independent DMD/LDC oracles and explicit variant
limits.
None changes the research-only status or admits a public API.
For JPEG specifically, the RGB8 transforms in the internal oracle are not a
proposed production colour API: native components and explicit `color-d`/
application conversion are the research direction in
`docs/research/JPEG_COLOR_BOUNDARY.md`. The native-plane, explicit signalling,
bounded I/O-failure and independent malformed-seed probes are documented in
`docs/research/JPEG_GATE_PLAN.md`. Source/sink and partial-write admission
questions remain open in `docs/research/JPEG_SOURCE_SINK_CONTRACT.md`.
An additional research-only native-plane read–modify–write surrogate now
preflights EXIF/ICC and unknown APP/COM markers, then checks explicit metadata
copy or discard; it is not a real editor or `imagery-d` consumer test.
