# Image I/O capability matrix — research evidence, not supported formats

Status: 2026-11-08 local research checkout. "Probe" means an experiment under
`experiments/`, not a public DUB package, stable API or complete format claim.
Read and write evidence are separate. Real application consumer tests are
currently unavailable; `dunia` is not ready.

| Format candidate | Read evidence | Write evidence | Important unqualified areas |
|---|---|---|---|
| PNG | Pure-D bounded probe: non-interlaced gray, gray+alpha, RGB, RGBA at 8/16 bits; packed grayscale 1/2/4 and indexed 1/2/4/8 native reads with PLTE/tRNS payload; all five filters, split IDAT, zlib/CRC. Independent Pillow/ImageMagick/Python fixtures and public external consumer under DMD/LDC. | Non-interlaced gray/RGB/alpha and packed/indexed output with PLTE/tEXt policy; caller-owned source and explicit sink/limit/failure results. Output independently decoded byte-exactly. | Adam7/APNG, semantic colour/profile interpretation and arbitrary ancillary metadata remain explicitly unsupported; real editor integration and performance qualification remain M5 work. |
| Classic TIFF | Bounded parser and uncompressed strip/tile/planar/ROI research; Deflate, PackBits, LZW and JPEG-in-TIFF consumers against GDAL fixtures. | Pure-D little-endian 8/16-bit gray/gray+alpha/RGB/RGBA writer with multi-strip output, technical metadata policy and GDAL exact-pixel oracle under DMD/LDC. | Broader malformed corpus, full metadata round-trip and real application integration remain open. |
| BigTIFF | 64-bit IFD/range parser and separate-window Deflate strip/tile research oracle. | BigTIFF strip/tile writers for uncompressed, Deflate, PackBits, LZW and baseline JPEG tiles; GDAL public consumer validates declared dimensions/types/compression. | Full metadata/IFD semantics, sparse payload/performance qualification and production range source remain open. |
| GeoTIFF / COG | Contract-only georeferencing and COG access gates; BigTIFF range experiment is not a COG reader. | None. | GeoKey oracle, overviews, range cost, source revision, satellite-product semantics and writer. |
| JPEG | Pure-D baseline 8-bit gray/YCbCr 4:4:4/4:2:2/4:2:0 decoder, metadata scanner, DMD/LDC independent Pillow/ImageMagick corpus and bounded mutation probes. | Caller-owned baseline writer with quality 1–100, restart interval and opt-in opaque EXIF/ICC copy or explicit discard; DMD/LDC public consumer passes. | Progressive/CMYK, integrated metadata/loss policy, optimized entropy/performance, real-world/security corpus and actual application consumer remain open. |
| GIF, BMP, WebP, AVIF, HEIF | No imageio-d evidence. | No imageio-d evidence. | Candidate inventory only; priority and exact read/write subsets need future consumer evidence and independent gates. |

## Decision rules

- "Common format" is a product-coverage objective, not an assertion that every
  variant is implemented or that read implies write.
- Every format/direction needs declared input/output representations, metadata
  fidelity/loss, malformed-input and resource limits, independent oracle,
  DMD/LDC results and consumer-visible performance before admission.
- GDAL, Pillow and ImageMagick are fixture generators/oracles, never runtime
  backends of the Pure-D imageio experiment.
- `imageio-d` owns encoded format mechanics; `raster-d` owns generic buffers
  and views; `color-d` owns colour mathematics; `imagery-d` owns semantic image
  interpretation. A consumer-shaped probe cannot replace actual application
  integration when that later becomes possible.
