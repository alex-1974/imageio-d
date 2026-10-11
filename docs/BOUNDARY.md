# Boundary proposal — not yet an accepted ADR

- `raster-d`: numeric sample storage, validated views, strides/planes, ROIs,
  retained resource lifetimes, generic raster transforms and reductions.
- `color-d`: colour-space value types, transfer functions, gamut and compositing
  mathematics; no decoder-specific ownership.
- `imagery-d`: image-band meaning, stored versus physical values,
  alpha/NoData/validity distinctions, colour bindings, radiometry, presentation
  and image-domain processing. Processing must work without file I/O.
- `imageio-d` candidate: encoded representations, format drivers, technical
  byte access, decode/encode, native sample/metadata extraction and direct
  caller-owned or raster-owned destination when justified.
- Application/adapter: choose source, connect decoded technical metadata to
  requested imagery semantics, select CRS/georeferencing integration.

The accepted M2 model must be reviewed before assigning SourceId,
ResourceId/Revision, AccessBackend, caches or materialization scheduling to
any new package. Use one concrete end-to-end reference rather than assuming
that moving the decoder means moving all three cache tiers.
