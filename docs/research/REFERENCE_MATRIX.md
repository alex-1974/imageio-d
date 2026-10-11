# Reference matrix — research starting point (not validated findings)

| System | Scope to inspect | Known architectural concern |
|---|---|---|
| Gamut (D) | decoder/encoder formats, 8/16-bit samples, `@safe`/`@nogc` claims | native pixel representation versus `raster-d` |
| imageformats (D) | pure-D baseline and API | format and metadata coverage |
| OpenImageIO | `ImageInput`, `ImageOutput`, plugins, tiles/scanlines | external C++ dependency and ABI |
| GDAL | windowed RasterIO, COG, GeoTIFF, metadata, drivers | broad geospatial dependency and driver semantics |
| libvips | demand-driven regions and streaming | implementation model versus duplicate framework |

Primary references:
- https://codemirror.dlang.org/packages/gamut
- https://codemirror.dlang.org/packages/imageformats
- https://openimageio.readthedocs.io/en/latest/imageinput.html
- https://gdal.org/en/stable/tutorials/raster_api_tut.html
- https://www.libvips.org/API/current/how-it-works.html

Fill with pinned versions, measurements and actual tests during R1/R2.
