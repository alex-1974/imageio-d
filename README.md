# imageio-d — Image I/O research

**Status: research only — no production package/API admitted.**

Research whether a small, independent image I/O library for D provides a
coherent, reusable boundary between encoded image formats/transport and
already-decoded numeric raster/image processing. Investigate existing D
libraries first; implement only when a consumer-driven experiment shows a
capability gap and the repository's admission gate is satisfied.

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
- Encode/write only where supported and justified, with explicit format,
  representation, failure and metadata-loss policies.
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

`imageio-d` and `imagery-d` should remain decoupled. Whether `imageio-d`
directly depends on `raster-d` or returns a minimal decoded descriptor to an
adapter is an open research question; do not freeze it prematurely.

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
No production `dub.sdl`, `source/` tree, public module root or release baseline
exists. Follow `AGENTS.md`, `ROADMAP.md` and current workspace engineering
rules. The first implementation must be a measured consumer vertical slice.
