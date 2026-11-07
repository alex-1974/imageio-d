# ADR 0005 — Provisional reader/request/result shape

## Status

Accepted as a research shape; not admitted as public API.

## Decision

The preferred shape for the first consumer slice is:

```text
source → reader → info → read request → owned or caller-owned result
```

This is the **reader-side first research slice**, not the full product API.
Writer/encoder shape remains open under ADR 0006 and Flow F in
`docs/research/API_SKETCHES.md`.

The vocabulary selected for ongoing internal probes is recorded in
`docs/research/INTERNAL_API_CONTRACT.md`. It is a research contract for
cross-experiment consistency, not a public API freeze or admission decision.

Provisional consumer-facing vocabulary:

```text
ImageSource -> ImageReader -> ImageInfo -> ReadArea -> ReadResult
                                           \-> ImageBuffer
```

Provisional module responsibilities:

```text
imageio.source    encoded file, memory and stream sources
imageio.reader    opened format reader and lifetime
imageio.metadata  technical dimensions, channels and representation
imageio.request   region, bands, destination and explicit conversion intent
imageio.result    coverage, layout, ownership and technical provenance
imageio.error     structured status/result errors
imageio.internal  parser, codec and compiler-tuning implementation
```

Consumer-facing names must remain understandable without knowledge of TIFF,
COG or codec internals. Terms such as IFD, GeoKey, tile block, predictor and
range window are internal implementation or diagnostic vocabulary, not public
entry-point names.

The first public slice should prefer inspection plus explicit reads over a
single convenience `decode()` function. Native samples, destination storage,
strides and semantic bindings must remain visible in the call shape.

## Rejected for now

- a monolithic `Image` that is simultaneously source, metadata and storage;
- implicit RGBA or colour conversion;
- a public universal plugin registry;
- public scheduler/cache abstractions;
- production module names copied directly from the research prototypes.

## Gate

Before admission, compile examples must be reviewed with a real consumer,
DDoc-rendered, and checked against the final `raster-d` vocabulary.
