# ImageRegion contract

`ImageRegion` is a technical decoded-image handoff. It is independent of
`raster-d` and `imagery-d`.

## Ownership

`ImageRegion.data` owns its decoded byte payload in the current allocating
decoder path. A consumer may copy it into another owner, for example a
`raster-d` lease. The imageio decoder does not return a borrow into a
transport buffer.

## Coordinates

`originX` and `originY` identify the region in the selected image level.
They are image coordinates, not CRS coordinates.

For a native component plane, `ImagePlane.originX/Y` are integer indices in
that plane's storage grid. `referenceOffsetX/Y` retain the fractional
position of the first stored plane sample relative to the requested
reference-grid boundary. With spacing `h/v` derived from the component
sampling factors, the first sample position is:

```text
referenceX = originX * h + referenceOffsetX
referenceY = originY * v + referenceOffsetY
```

The offsets are exact rationals. An odd crop therefore cannot silently lose
subsampling phase through integer division. `PlaneSamplingGeometry.status`
must be `known` before a consumer treats the source phase as usable;
`unavailable`, `unsupported`, `conflicting` and `invalid` are explicit
non-interpretable states.

## Layout

`ImageRegionInfo` describes the byte layout explicitly:

- `sampleFormat` identifies the native sample representation;
- `componentCount` identifies the number of technical components;
- `layout` distinguishes interleaved and planar storage;
- stride fields are byte strides and must be nonzero for an explicitly
  strided region.

The current decoder emits tightly packed regions. Consumers must not infer
RGB(A), alpha, NoData, radiometry, colour space or CRS semantics from the
technical component count.

TIFF inspection exposes GeoTIFF as technical presence/count metadata
(`geoKeyDirectoryCount`, `modelPixelScaleCount`, `modelTiepointCount`,
`modelTransformationCount`, and `noDataCount`). These fields deliberately do
not construct CRS objects, apply transforms, or convert NoData into masks or
alpha; those operations remain consumer/domain responsibilities.

When present, `geoKeyDirectoryValues` preserves the validated unsigned-short
GeoKeyDirectoryTag payload in source order. It is a technical directory, not a
resolved CRS. Unknown keys and consumer-specific interpretation remain
available to the caller instead of being silently discarded.

The TIFF decode result also carries `sourceInfo` for the selected IFD level.
This keeps technical compression, tiling, predictor, GeoKey, affine-tag and
NoData facts attached to the decoded region without copying them into raster
or imagery semantics. `noDataValue` preserves the source tag bytes; consumers
must choose explicitly whether and how to turn that declaration into a
validity mask.

`TiffImageInfo.geoKeyShort(keyId, value)` provides a bounded lookup for
GeoKeys whose value is an inline SHORT. The directory header and entry bounds
are validated before lookup. Keys backed by ASCII/DOUBLE/other TIFF tags are
not guessed or coerced; callers can inspect the preserved directory and tag
metadata explicitly.

The inspection result additionally exposes presence-qualified technical IDs
for GeoTIFF model type, raster type, geographic CRS and projected CRS. These
are numeric source identifiers only; resolving them into CRS definitions or
performing coordinate operations belongs above image I/O.

## Lifetime and mutation

The returned region remains valid until its owning `ImageRegion` value is
destroyed or its `data` storage is changed. Consumers must copy before
retaining data beyond that lifetime. Imageio does not mutate a returned
region after publication.

## Future streaming

A future callback/tile API may provide borrowed regions. That API must be a
separate contract and must state callback-scoped lifetime explicitly; it does
not change the allocating `ImageRegion` contract above.
