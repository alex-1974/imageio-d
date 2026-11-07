# Roadmap — research and admission gates

## M0 — Scope and product hypothesis (CURRENT)

- Pure-D implementation is the intended direction from the first production
  slice; no C/C++ backend or wrapper is part of the target architecture.
- Existing libraries remain comparison references, not dependencies.
- The first experiment must be narrow: one format family and a
  consumer-shaped vertical slice are preferable to a speculative codec suite.
- API ergonomics, naming, module structure and ownership vocabulary are
  admission criteria alongside codec correctness.

Exit evidence: accepted ADRs 0001/0002, a pinned comparison matrix, concrete
consumer flows and a research plan with independent correctness oracles.

## M1 — Responsibility / dependency boundary

- Confirm what belongs to image I/O, `raster-d`, `imagery-d`, `color-d`,
  Pure-D format modules, and application source selection.
- Map `imagery-d` ADR 0003 Source/Resource/Locator/AccessBackend/Decoder and
  L1/L2/L3 cache boundaries; do not implicitly overturn that accepted model.
- Decide which existing libraries are reference-only and which Pure-D format
  capability is independently reusable.
- Record `adopt`, `reference only`, `defer`, or `reject` for each candidate.

## M2 — Audit existing implementations

Compare Gamut, imageformats, OpenImageIO, GDAL and libvips. Capture exact
versions, licences, runtime dependencies, supported sample/channel formats,
stream access, metadata fidelity, error handling, and decoder safety.

## M3 — API and consumer experiments

Draft competing APIs for file, memory and stream input; inspection; native
window reads; caller-owned output; owned results; encoding to a file or
caller-owned sink; explicit representation/options and metadata-loss policy;
metadata transfer; and structured read/write errors. Evaluate them against
real D snippets and the `raster-d` and `imagery-d` vocabulary. Do not
implement production types yet.

## M4 — Codec, ownership and performance experiments

Current initial format experiment: bounded Pure-D TIFF core (ADR 0003).
This does not narrow the product requirement to TIFF or reading only.
JPEG/PNG read and write, TIFF write and other consumer-justified formats need
their own gates; GeoTIFF, BigTIFF, compression and COG remain separate gates.

Proof cases (minimum):
- PNG RGB/RGBA including alpha metadata;
- TIFF/GeoTIFF native 16-bit multiple-band sample preservation;
- a large windowed/tiled dataset (GeoTIFF/COG) versus forced full decode;
- non-file in-memory/generated source bypass;
- negative tests: truncation, malformed metadata, unsupported type/codec;
- borrowed/retained lifetime after decoder and cache disposal;
- memory peaks, buffer copies, exact ROI equivalence and byte amplification.

No promise that every format module supports every variant or both directions
before its own gate passes. External libraries are oracles, not runtime backends.

The three prospective read/write flows (general image editor, scientific image
editor and `dunia` satellite analysis) are defined in
`docs/research/CONSUMER_READ_WRITE.md`. Real consumer tests are not currently
possible; `dunia` is not yet ready. Continue bounded format and API research
with independent oracles and clearly labeled consumer-shaped probes. Before
public API admission, exercise an actual read-to-processing-to-write flow
across the real library boundaries. Do not equate an oracle decoder with a
production runtime backend or a surrogate probe with real consumer evidence.

## M5 — Explicit admission decision

Demand one real read/write consumer path, independent correctness
oracle/reference, reproducible corpus, memory/ownership/failure contracts,
DMD/LDC matrix,
optimized LDC benchmarks, and documented trade-offs. If direct dependencies
or narrow adapters are sufficient, reject the standalone production package.
This gate remains open until an actual consumer is available; it does not
prevent research-only probes or format experiments in M3/M4.

## M6 — Conditional implementation

Only if M5 accepts a coherent standalone domain: define DUB package, public
Ddoc/API, module naming and minimal Pure-D format modules, positive/negative
compile contracts, CI/release gates, licence and consumer smoke. Avoid
speculative scheduler, cache, backend-wrapper or universal-plugin features.

Current completion tracker: `docs/research/ADMISSION_CHECKLIST.md`.
Provisional next format-gate research priorities, conditional on actual
consumer evidence, are in `docs/research/NEXT_FORMAT_GATE_PRIORITY.md`.

Separate follow-up gates for compression, BigTIFF, GeoTIFF/COG, PNG and JPEG
are defined in `docs/research/FORMAT_GATES.md`. They are not included in the
bounded uncompressed TIFF admission decision.
