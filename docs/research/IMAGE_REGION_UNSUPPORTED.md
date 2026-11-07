# Neutral ImageRegion unsupported capabilities

The current research contract intentionally does not promise the following:

- chroma upsampling, YCbCr/RGB conversion, clipping or normalization;
- inference of component roles from array position when the source does not
  signal them;
- treating unavailable or unsupported plane geometry as centred or cosited;
- construction of CRS objects, reprojection or spatial/OSM matching;
- conversion of NoData into masks, alpha or zero values;
- borrowed streaming regions with a lifetime beyond the callback;
- complete progressive, CMYK, arbitrary JPEG colour and all TIFF variants;
- Adam7/APNG and complete PNG ancillary-metadata transfer;
- a universal source scheduler, cache or cancellation framework;
- a stable released package or frozen public API.

When a requested operation falls outside the current research subset, the
decoder must return a structured failure or explicit metadata state. A
successful native decode does not authorize a consumer to fill in omitted
image semantics.
