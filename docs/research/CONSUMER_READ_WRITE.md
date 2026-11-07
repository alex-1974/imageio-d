# Read/write consumer contract

Status: research requirements, not supported API or implemented format list.
The owner boundary is ADR 0006. A format's read and write capabilities must
be recorded separately; "common formats" is a product coverage goal, not a
claim that current probes cover them.
The current per-format status is in `CAPABILITY_MATRIX.md`.

## Availability and evidence levels

`dunia` is not yet ready for integration, and real consumer tests for these
flows are currently unavailable. The rows below are **target profiles**, not
observed application behavior or passed consumer tests. Do not invent
`dunia` files, export needs, usage frequencies or performance budgets.

Work that can proceed now: independently generated and hashed format fixtures,
external decode/encode oracles, malformed-input and limit tests, DMD/LDC
probes, performance baselines, and small standalone **consumer-shaped**
compile/API sketches. Such probes validate codec and boundary hypotheses but
do not prove real application usability. Keep the distinction explicit in
reports and checklists. Real integration is deferred until a consumer is
available; it remains an unmet public-admission gate rather than a reason to
stop format research.

## Reference flows

| Consumer | Read path to exercise | Write path to exercise | Evidence still needed |
|---|---|---|---|
| General image editor | Inspect/open an ordinary image, retain technical alpha/profile/orientation metadata, decode into caller-owned raster storage. | After explicit imagery/colour choices, encode a chosen representation with visible format options and metadata-loss policy. | Real application calls; JPEG/PNG read-and-write fixtures, independent oracles, unsupported-mode and malformed-input errors. |
| Scientific image editor | Read native high-depth, float or multiband samples without normalization; inspect metadata before expensive decode; read a non-origin region where the format permits. | Export selected native representation and technical metadata without unrequested sample reduction. | Representative data types, exact lossless round-trip values, ROI/whole equivalence, peak memory and copy counts. |
| `dunia` satellite analysis | Read a representative satellite product's native bands and technical georeferencing into `raster-d` storage; bind product meaning explicitly in `imagery-d`. | Export an explicitly selected analysis result if the workflow requires it; the target format and metadata policy remain to be specified by `dunia`. | Actual input/output formats, sample types, bands, window sizes, georeferencing, revision and lifetime requirements; one real end-to-end consumer probe. |

For every flow, generated or in-memory imagery must remain usable without
opening an encoded source. The application/adapter chooses whether to use
`imageio-d`; `imagery-d` remains an independent image-processing consumer of
`raster-d`.

## Shared acceptance checks

- Inspect technical metadata without a hidden full pixel decode; expose when
  a requested region requires a full decode or extra I/O.
- Decode into documented owned or caller-owned storage with explicit stride,
  sample representation, lifetime, limits and failure state.
- Keep technical facts separate from image meaning: no implicit band-to-RGBA,
  digital-number-to-physical-value, NoData-to-alpha or CRS binding.
- Make encoder input representation, destination ownership, format options,
  lossy/lossless behavior, partial-write policy and metadata-loss policy clear.
- Check lossless read/write with exact native samples and an independent
  decoder; use an explicit quality metric/tolerance for lossy output.
- Test DMD and LDC, malformed data, unsupported variants, destination/scratch
  limits, source/result lifetimes, and consumer-visible performance.

## Capability matrix to fill as evidence becomes available

Each candidate format needs separate cells for read and write, supported
sample/channel variants, alpha, colour profiles, orientation, technical
metadata, region cost, animation/multipage behavior if applicable, resource
limits, independent oracle and known losses. JPEG, PNG and TIFF are explicit
research candidates; GeoTIFF/COG address the satellite flow. Additional
formats are not admitted merely because they are widespread. Neither the
current TIFF prototypes nor the external GDAL/ImageMagick oracles count as
runtime backends.

When `dunia` is ready, ask which satellite product(s) and exact files, local
or ranged/remote access, typical ROI, band/sample types, metadata needed for
interpretation, and whether export is part of its first workflow. Until those
answers are backed by evidence, do not infer a `dunia` export format.
