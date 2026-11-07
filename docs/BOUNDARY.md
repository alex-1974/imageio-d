# Boundary proposal — research contract, not production API

- `raster-d`: numeric sample storage, validated views, strides/planes, ROIs,
  retained resource lifetimes, generic raster transforms and reductions.
- `color-d`: colour-space value types, transfer functions, gamut and compositing
  mathematics; no decoder-specific ownership.
- `imagery-d`: image-band meaning, stored versus physical values,
  alpha/NoData/validity distinctions, colour bindings, radiometry, presentation
  and image-domain processing. Processing must work without file I/O.
- `imageio-d`: encoded representations, Pure-D format parsers/decoders/encoders,
  technical byte access, decode/encode, native sample/metadata transfer,
  explicit format capabilities and direct caller-owned or `raster-d`
  destination/source when justified.
- Application/adapter: choose source and export target; connect technical
  metadata to requested imagery semantics; select colour, radiometric and
  CRS/georeferencing interpretation and any intentional conversion.

The accepted M2 model must be reviewed before assigning SourceId,
ResourceId/Revision, AccessBackend, caches or materialization scheduling to
any new package. Use one concrete end-to-end reference rather than assuming
that moving the decoder means moving all three cache tiers.

`imageio-d` must not become a second raster engine, image-semantic layer,
colour-management engine, general scheduler or cache framework. It reports
technical capabilities and costs honestly: a requested window may be served
by tiles, strips or a full decode, and the observable behaviour must be tested.
The same rule applies on write: codec-required transforms belong to format
I/O, but optional colour management and image interpretation do not. Encoding
options, partial-write behavior, lossy quality and metadata loss must be
visible to the caller. See ADR 0006 for the three consumer flows.
