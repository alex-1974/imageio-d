# Roadmap — research and admission gates

## R0 — Responsibility / dependency boundary (CURRENT)

- Confirm what belongs to image I/O, `raster-d`, `imagery-d`, `color-d`,
  future GDAL adapters, and application source selection.
- Map `imagery-d` ADR 0003 Source/Resource/Locator/AccessBackend/Decoder and
  L1/L2/L3 cache boundaries; do not implicitly overturn that accepted model.
- Decide if there is an independent reusable domain or if existing decoder
  bindings plus narrowly scoped adapters are sufficient.
- Record `adopt`, `adapt`, `depend`, `reference only`, `defer`, or `reject`.

## R1 — Audit existing implementations

Compare Gamut, imageformats, OpenImageIO, GDAL and libvips. Capture exact
versions, licences, runtime dependencies, supported sample/channel formats,
stream access, metadata fidelity, error handling, and decoder safety.

## R2 — Consumer and ownership experiments

Proof cases (minimum):
- PNG RGB/RGBA including alpha metadata;
- TIFF/GeoTIFF native 16-bit multiple-band sample preservation;
- a large windowed/tiled dataset (GeoTIFF/COG) versus forced full decode;
- non-file in-memory/generated source bypass;
- negative tests: truncation, malformed metadata, unsupported type/codec;
- borrowed/retained lifetime after decoder and cache disposal;
- memory peaks, buffer copies, exact ROI equivalence and byte amplification.

No promise that every candidate backend handles every format.

## R3 — Explicit admission decision

Demand one real consumer, independent correctness oracle/reference,
reproducible corpus, memory/ownership/failure contracts, DMD/LDC matrix,
optimized LDC benchmarks, and documented trade-offs. If direct dependencies
or narrow adapters are sufficient, reject the standalone production package.

## R4 — Conditional implementation

Only if R3 accepts a coherent standalone domain: define DUB package,
public Ddoc/API, module naming and minimal backend(s), positive/negative
compile contracts, CI/release gates, licence and consumer smoke. Keep format
plugins optional and avoid speculative scheduler/framework features.
