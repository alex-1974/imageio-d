# Image I/O capability matrix — research evidence, not supported formats

Status: 2026-10-28 local research checkout. "Probe" means an experiment under
`experiments/`, not a public DUB package, stable API or complete format claim.
Read and write evidence are separate. Real application consumer tests are
currently unavailable; `dunia` is not ready.

| Format candidate | Read evidence | Write evidence | Important unqualified areas |
|---|---|---|---|
| PNG | Pure-D bounded probe: non-interlaced gray, gray+alpha, RGB, RGBA at 8/16 bits; packed grayscale 1/2/4 and indexed 1/2/4/8 native reads with PLTE/tRNS payload; all five filters, split IDAT, zlib/CRC. Whole-file input but row-bounded IDAT-slice decoder. Independent Pillow/ImageMagick/Python fixtures under DMD/LDC. | Pure-D filter-0/adaptive fixed-LZ, provider-backed bounded hash-chain Deflate and fast stored-row encoders for 8/16-bit non-indexed shapes. Caller-owned full output or pull-style per-row IDAT chunks. Separate same-shape metadata-transfer probe preserves safe chunks and opt-in known colour chunks. Output independently decoded byte-exactly. | Indexed/packed write, semantic metadata editing, Adam7/APNG, colour/profile interpretation, source streaming, multi-fixture speed/size qualification and provider-side hash-chain zlib framing. Loss requires explicit drop policy. |
| Classic TIFF | Bounded parser and uncompressed strip/tile/planar/ROI research; PackBits probes; separate `compression-d` Deflate consumer against GDAL fixtures. | Pure-D one-strip uncompressed little-endian 8/16-bit gray/gray+alpha/RGB/RGBA research writer; GDAL exact-pixel oracle under DMD/LDC. | Compressed, tiled, multi-strip, metadata and BigTIFF write; broad malformed corpus. No general TIFF support claim. |
| BigTIFF | 64-bit IFD/range parser and separate-window Deflate strip/tile research oracle. | None. | Full metadata/IFD semantics, complete sparse payload oracle, writer and production range source. |
| GeoTIFF / COG | Contract-only georeferencing and COG access gates; BigTIFF range experiment is not a COG reader. | None. | GeoKey oracle, overviews, range cost, source revision, satellite-product semantics and writer. |
| JPEG | Pure-D research decoder for baseline 8-bit gray/YCbCr 4:4:4/4:2:2/4:2:0 single scan, including DRI/RST; separate borrowed EXIF/ordered-ICC header scanner; DMD/LDC versus independent Pillow/ImageMagick corpus, explicit unsupported variants and bounded mutation probes. Cross-MCU chroma regression has ≤3 same-file delta on 17×19 and 257×193 synthetic cases with padded stride; 1×19 follows a different interpolation policy than libjpeg-turbo (delta 27). | Pure-D caller-owned baseline gray/YCbCr 4:4:4/4:2:2/4:2:0 writer with quality 1–100, restart interval and opt-in opaque EXIF/ICC copy or explicit discard. DMD/LDC release oracles include small and synthetic 256×256 output. | Representative chroma/image quality, progressive/CMYK, integrated metadata/loss policy, optimized entropy/competitive performance, real-world/security corpus, source/sink contract and actual consumer. Separate Gate J, no public support. |
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
