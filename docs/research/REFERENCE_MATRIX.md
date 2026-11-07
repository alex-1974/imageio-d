# Reference matrix — research starting point (not validated findings)

| System | Scope to inspect | Known architectural concern |
|---|---|---|
| Gamut (D) | decoder/encoder formats, 8/16-bit samples, `@safe`/`@nogc` claims | native pixel representation versus `raster-d` |
| imageformats (D) | pure-D baseline and API | format and metadata coverage |
| OpenImageIO | `ImageInput`, `ImageOutput`, plugins, tiles/scanlines | external C++ dependency and ABI |
| GDAL | windowed RasterIO, COG, GeoTIFF, metadata, drivers | broad geospatial dependency and driver semantics |
| libvips | demand-driven regions and streaming | implementation model versus duplicate framework |

These projects are references and comparators only. The target `imageio-d`
architecture is Pure D and must not hide a native backend behind a wrapper.

## Comparison dimensions

For each candidate record exact version, licence, build/runtime dependencies,
format coverage, native sample types, channel model, metadata fidelity,
memory/stream input, tile/strip/window/overview support, caller-owned output,
error behaviour, malformed-input limits, thread-safety, D integration effort,
and measured time, peak RSS, I/O bytes and copies.

## D-native references

| Library | Initial hypothesis to verify |
|---|---|
| Gamut | strongest Pure-D general-image reference; inspect API ergonomics, native samples, metadata and window limitations |
| imageformats/imagefmt | lightweight Pure-D baseline; inspect simplicity versus limited metadata and raster semantics |

Primary references:
- https://codemirror.dlang.org/packages/gamut
- https://codemirror.dlang.org/packages/imageformats
- https://openimageio.readthedocs.io/en/latest/imageinput.html
- https://gdal.org/en/stable/tutorials/raster_api_tut.html
- https://www.libvips.org/API/current/how-it-works.html

## Initial evidence snapshot (2026-10-24)

| System | Observed baseline | Initial result |
|---|---|---|
| Gamut | DUB 3.5.0 | Pure D; PNG/JPEG/JPEG XL/WebP/TGA/GIF/BMP/DDS/QOI-family; 8/16-bit and float image types; memory and callback I/O; monomorphic image model; no geospatial window contract identified yet |
| imageformats | DUB 7.0.2 | Pure D baseline; PNG/TGA/BMP/JPEG; mostly 8-bit output, PNG also 16-bit; simple conversion-oriented API; limited metadata/window evidence |
| OpenImageIO | documentation 3.3.0 | scanlines, tiles, strides, subimages/mip levels and rich ImageSpec; C++17 implementation and substantial optional/native dependency surface |
| GDAL | current stable documentation | band/block metadata, NoData, overviews, windowed RasterIO, caller buffer, type conversion and resampling; broad native geospatial runtime |
| libvips | current documentation | demand-driven, low-memory processing and broad format coverage; processing framework is wider than the target I/O boundary |

This snapshot is directional, not an admission result. Versions, licences,
platforms, exact capabilities and measurements must be pinned in experiment
records before implementation decisions.
