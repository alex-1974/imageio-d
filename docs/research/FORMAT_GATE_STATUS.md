# Format gate status

## Bounded classic-TIFF core

The selected uncompressed reader corpus now passes independent GDAL raw-pixel
comparison under DMD/LDC for gray8, RGB8 and native gray16 single strips,
planar RGB8 strips and tiled gray16 including edge and non-origin ROI cases.
The planar path preflights all block ranges and writes strip samples directly
into caller-owned interleaved output with zero full-image staging. The
1024×1024 probe reports one destination copy per payload byte and repeated
peak RSS. Negative coverage includes malformed headers/IFDs, invalid and
mismatched counts, external arrays outside the file, overlapping blocks,
short payloads/destinations, arithmetic overflow and unsupported sample or
compression representations. This closes the local correctness and resource
items for the bounded core; second-host evidence and a real consumer remain
open admission gates.

## Compression

PackBits has an initial Pure-D, `@safe @nogc nothrow` decoder probe under DMD
and LDC. It is now connected to a caller-supplied scratch-buffer strip bridge
and passes an externally generated PackBits TIFF fixture against GDAL raw
output under DMD and LDC. Four-strip and one-tile PackBits fixtures now pass.
The caller-owned Scratch-Buffer is the hard expansion limit: no unbounded
decompression buffer is allocated. Truncated literals/runs and insufficient
destinations are covered under both compilers. The public writer gate now also
qualifies Deflate, PackBits, LZW and JPEG BigTIFF tile writers through GDAL.

The workspace-size API and separate `workspaceTooSmall` status are implemented
in the experimental TIFF slice. A separate `compression_consumer` experiment
now declares a local DUB path dependency on Pure-D `compression-d`, validates
Deflate strips/tiles against 11 GDAL fixtures under DMD/LDC, and preserves the
research-only imageio API boundary. TIFF-LZW remains a separate gate.

## BigTIFF

The BigTIFF research reader now checks the header, 64-bit first-IFD offset,
entry count, 20-byte entries, supported type widths, inline/external value
ranges and next-IFD offset. It reads SHORT/LONG/LONG8/IFD8 unsigned entries.
The bounded multi-IFD traversal detects cycles and directory-count limits.
Synthetic malformed cases, a GDAL-generated metadata oracle and a sparse-file
IFD window above 4 GiB pass under DMD/LDC via
`experiments/tiff_core/bigtiff_oracle.sh`. The sparse test verifies correct
64-bit range addressing without allocating a 4-GiB byte slice. The
`compression_consumer` experiment additionally decodes BigTIFF Deflate strips
and tiles from separately read IFD, external offset/count and compressed-block
windows. It compares native pixels with a GDAL oracle under DMD/LDC; rebased
block windows above 4 GiB, short scratch and missing ranges are probed.
The bridge stages one decoded block in caller-owned memory before committing
it. 8-/16-bit RGB Predictor-2 strip/tile fixtures, strided destination padding
and reordered window lookup pass under DMD/LDC. The range bridge needs two
caller-owned decoded-block buffers; file-ordered/index-matched ranges take a
linear validation path. Full metadata semantics and a production range-source
API remain open.

## GeoTIFF

The gate is currently contract-only. Technical GeoTIFF keys may be preserved
by imageio-d, while CRS/product binding remains above the I/O boundary. The
first generated metadata-oracle fixture is now under
`experiments/geotiff_metadata/`: it creates a 17x13 tiled, DEFLATE-compressed
UInt16 GeoTIFF with EPSG:32612, a north-up affine transform and NoData=0,
then records GDAL JSON plus a truncated negative fixture. The fixture script
is evidence for a future Pure-D parser, not a GDAL runtime dependency or a
public API. GeoKey-directory mutation cases and the corresponding Pure-D
comparison probe remain open. The internal `ifd_result` inspection probe now
records technical photometric/predictor/tile fields, NoData and GeoTIFF
directory references and passes against this fixture under DMD/LDC. It still
returns references to encoded tag values; decoding GeoKey semantics and
constructing CRS objects remain deliberately outside this layer.

The same fixture now has a local range-source probe that copies only caller-
requested byte intervals, counts requests/bytes and rejects out-of-bounds
ranges. It passes under DMD/LDC; it is a measurement seam for later COG work,
and now reports encoded/decoded byte amplification. It remains a measurement
seam, not an HTTP, cache or scheduling abstraction.

`check_range_decode.sh` now connects the local tiled BigTIFF fixture to the
separate-range Deflate bridge. IFD, offset/count and compressed tile payloads
are supplied as independent ranges; native pixels match the GDAL oracle under
DMD/LDC for strip and tile layouts. This is the first direct range-to-decoder
evidence, while remote HTTP COG behavior remains open. An internal
overview-aware planner now maps a requested base-resolution area to the
selected overview area and clamps it to level bounds under DMD/LDC. It does
not resample or perform HTTP access.

The existing research-only `compression-d` consumer now also exposes a checked
pixel-window Deflate path. It inflates only intersecting tiles into a
window-sized caller-owned buffer, undoes Predictor 2 in file byte order and
passes native UInt16 comparisons under DMD/LDC. This closes only the bounded
classic tiled/Deflate probe; it does not admit a general TIFF/COG API.

The overview probe now generates 2x/4x reduced-resolution levels, records the
GDAL overview sizes as an oracle, and exercises an explicit technical level
selector under DMD/LDC. The selector reports no level when the requested
resolution is finer than the base image; it does not resample or make a
quality decision. The window decoder now reports the selected native-block
path, window coverage, decoded block count and compressed bytes; its DMD/LDC
probe reports one intersecting block for the 7x6 test window. Overview choice
is still a technical planning result, not a resampling promise.

The `experiments/raster_handoff/` probe now compiles against the local public
`raster-d` package under DMD/LDC. It transfers a caller-owned 7x6 UInt16 byte
buffer into retained `raster-d` ownership and accesses it through a
lease-bound view. The probe keeps imageio-d responsible for decoded bytes and
leaves storage ownership/lifetime with raster-d; it does not add a dependency
to the imageio-d research parser.

## COG

The gate is currently contract-only. The local range-reader and overview
probes are now complemented by `experiments/geotiff_metadata/sentinel_cog_compare.sh`.
Against the issue #3 Sentinel-2 B02 URL, GDAL reports 10980x10980 UInt16,
1024x1024 blocks and the expected north-up transform; the script emits a
32x24 native UInt16 window oracle (1536 bytes) and hashes. This is a
reproducible external comparison fixture, not a GDAL runtime dependency or an
imageio-d HTTP API. Offline qualification still requires a pinned local copy.

GDAL is available locally as an independent fixture/oracle generator; it is
not a runtime dependency of imageio-d.

## PNG

`experiments/png_rw/` contains a bounded Pure-D read/write **research probe**
using `compression-d`. DMD/LDC passes compare independently generated 8-/16-bit
gray/RGB/RGBA and all filter cases against Pillow/ImageMagick/Python oracles.
Packed 1/2/4-bit grayscale and indexed 1/2/4/8-bit native reads now pass;
indexed reads expose validated PLTE/tRNS payload rather than silently
expanding colour. Reader IDAT slices decode with two row buffers and no
compressed/full-image staging. The writer has a fast stored-block row mode
and a pull-style one-IDAT-per-row output path; its adaptive-filter fixed-LZ
mode gives much smaller files on the benchmark fixture but is still slow.
A temporary hash-chain Deflate probe achieved near-same size at much lower
latency on that one fixture. The active experiment now calls the corresponding
`compression-d` raw encoder, retaining only local zlib framing; the original
probe remains archived as evidence. Compression ownership remains with
`compression-d`.
The fresh `compression-d` remote-master provider at `b0fc8d7` now passes a
fully linked `-dip1000` PNG consumer check and the independent output oracle
under DMD/LDC. The tiny local zlib header/Adler wrapper remains a research
bridge; a provider one-shot API is deferred pending a stable contract and
additional consumer need. See `PNG_RW_BASELINE.md` for the pinned evidence.
The exercised write paths have independent output decode oracles. Chunk CRC/order,
split IDAT, short buffers, corrupt zlib, palette-index bounds and explicit
metadata loss are probed. A separate same-shape transfer probe retains safe
ancillary chunks, requires explicit applicability for known colour metadata,
and rejects or explicitly drops unknown unsafe chunks. Indexed/packed writer
support is now exercised by the public PNG consumer; broader semantic metadata
preservation, Adam7/APNG, chunked source input, balanced speed/size compression
and a public application API remain open. `PNG_RW_BASELINE.md` and
`PNG_EDITOR_GATE.md` record the measurements and unresolved contract. Gate P
remains an admission gate, not a failed local codec gate.

## Classic TIFF write

The public package now has caller-owned classic and BigTIFF writers for
8-/16-bit chunky strips/tiles, technical metadata, Deflate, PackBits, LZW and
baseline JPEG-in-TIFF. DMD/LDC output passes independent GDAL dimensions,
band/sample type, compression and native-pixel oracles. Full metadata
round-trip, large-file qualification and real application integration remain
open admission work.

## JPEG

JPEG read/write remains its own editor-driven research gate. The Pure-D
`experiments/jpeg_gate/` probe decodes baseline 8-bit gray/YCbCr 4:4:4,
4:2:2 and 4:2:0 single-scan files and writes those three sampling forms with
explicit quality 1–100, restart intervals and opt-in opaque EXIF/ICC copy or
explicit discard. A separate header scanner exposes borrowed EXIF and ordered
ICC segments. The research-only native-plane path avoids implicit colour
conversion; an audited read wrapper preflights EXIF/ICC, unknown APP/COM and
non-default JFIF/Adobe loss risks. A technical read–modify–write surrogate
checks explicit EXIF/ICC copy versus discard, including split ICC. These new
probes run with bounds checks and assertions under DMD/LDC; the separate
legacy codec stress suite also uses release builds. This is not an admitted
consumer API or real editor integration. DMD/LDC outputs reopen
with Pillow/ImageMagick; a synthetic 256×256 corpus and bounded mutation probes
extend the prior tiny fixtures. Progressive, CMYK, truncation, malformed
quantizer/Huffman and Adobe raw-RGB rejection are covered. The bounded
pull-based scanner now inspects the header through SOS from short-reading,
pausable sources with fixed state and pending-byte hand-off. A Linux pipe
probe confirms the hand-off on a real non-seekable source under DMD/LDC; it
does not incrementally decode entropy or pixels. The bounded
cross-MCU chroma regression now has ≤3-level same-file differences on
17×19 and 257×193 synthetic cases, including padded-stride/canary checks;
the 1×19 oracle uses a different narrow-image interpolation policy. Broader
image quality, complete metadata preservation/loss policy, a broad
real-world/security corpus, competitive performance, a true incremental
source/sink API and consumer validation
remain open. `JPEG_GATE_PLAN.md` records the evidence; no public format/API
admission follows.

The provisional next research-effort queue is in
`NEXT_FORMAT_GATE_PRIORITY.md`. It does not change the dependency sequence
or the real-consumer admission gate.

