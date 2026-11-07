# Admission decision — bounded Pure-D TIFF research slice

Status: research decision, not a release decision.

## Decision

The bounded uncompressed TIFF slice is **accepted as an internal research
capability** and **deferred as a public imageio-d API**.

The evidence is sufficient to continue with independent corpus work and
consumer-shaped API design. It is not sufficient to promise a general TIFF
implementation or a stable DUB package.

## Accepted evidence

- Header, IFD, external LONG-array, strip and tile bounds are checked without
  allocation in the structured result probes.
- Interleaved, planar, tiled, multi-strip and ROI byte traversal are covered by
  caller-owned destination probes.
- The complete selected uncompressed fixture corpus now passes independent
  GDAL raw-pixel comparison under DMD and LDC. Planar strips are copied
  directly into caller-owned interleaved output without a full-image staging
  buffer; copy counts and peak RSS are recorded.
- Invalid ranges, overlaps, truncation, unsupported compression, sample width
  and sample format have negative probes. External strip/tile fixtures also
  cover invalid and mismatched counts and out-of-range external arrays.
- DMD and LDC compile and execute the probes. Optimized measurements preserve
  observable output and report copied bytes/checksums.
- The isolated consumer probe demonstrates that explicit source revision and
  semantic bindings belong in a materialization key; imageio-d must not invent
  those bindings.

## Deferred evidence

- Repeated-run variance and a second host/compiler matrix are not established.
- Public module names, visibility and versioning remain provisional until the
  imagery-d consumer validation is run against the real repository boundary.
- The selected corpus remains deliberately bounded. It does not establish a
  general TIFF reader, security qualification or support for variants outside
  the explicitly tested representations.
- BigTIFF, compressed TIFF, GeoTIFF keys, COG transport, PNG interoperability
  and asynchronous scheduling are separate research tracks.

## Consequence

Research may proceed with internal probes and corpus tooling. No `dub.sdl`,
production `source/` tree, release tag or supported public API is added by
this decision. Promotion requires the remaining correctness, independent
comparison, performance and consumer gates in
`docs/research/ADMISSION_CHECKLIST.md`.

