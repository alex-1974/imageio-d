# Separate format gates

These gates extend the accepted bounded uncompressed TIFF research slice. Each
gate requires its own corpus, independent oracle, failure contract,
performance evidence and consumer justification. Passing one gate does not
admit the others.

## Gate C — TIFF compression

Ownership boundary: `imageio-d` owns TIFF compression-tag interpretation,
range planning and orchestration. Compression algorithms, bounded codec
implementations and their reusable streaming/buffer contracts belong in
`compression-d` and must be consumed there rather than reimplemented here.

Scope candidates:

- PackBits;
- Deflate;
- LZW;
- predictor handling;
- bounded decompression and output-size checks.

Research questions:

- Can decompression remain Pure-D and allocation-bounded?
- How are decompression bombs and declared-size mismatches rejected?
- Can a compressed strip/tile decode directly into caller-owned ROI output?
- Which codecs belong in the first supported subset, and why?
- What is the copy and throughput cost versus uncompressed TIFF?

Admission evidence:

- independently generated compressed fixtures;
- malformed/truncated/compression-bomb corpus;
- byte-equivalence against GDAL or another independent decoder;
- peak memory and expansion-ratio limits;
- DMD/LDC measurements.

## Gate B — BigTIFF

Scope:

- 64-bit offsets and byte counts;
- BigTIFF header and IFD entry layout;
- large-file bounds and overflow handling;
- compatibility boundary with classic TIFF.

Research questions:

- Can classic and BigTIFF share a checked reader without weakening bounds?
- Which public metadata fields must become 64-bit?
- How are files above 4 GiB tested without requiring a giant checked-in file?
- Does the caller-owned API remain identical?

Admission evidence:

- generated BigTIFF fixtures with small logical images;
- independent metadata and pixel oracle;
- 32-/64-bit overflow negatives;
- large-offset sparse-file or equivalent fixture evidence;
- no accidental narrowing in DMD/LDC builds.

## Gate G — GeoTIFF and COG

GeoTIFF metadata and COG access are separate sub-gates:

- GeoTIFF: technical georeferencing keys and metadata preservation;
- COG: HTTP/range access, overview selection, tile ordering and request cost.

Rules:

- imageio-d reports technical keys and source layout;
- imagery-d owns CRS/product binding, reprojection, NoData policy and
  resampling semantics;
- COG transport must not force a filesystem-only source API;
- range requests, cache identity and cancellation require imagery-d consumer
  validation.

Admission evidence:

- independent GeoTIFF metadata oracle;
- COG files with overviews and tiled data;
- local range-reader test before HTTP;
- request/ROI amplification and cache measurements;
- explicit source revision and retained-result lifetime evidence.

## Gate P — PNG read/write interoperability

PNG is an interoperability gate, not a reason to broaden the TIFF API.

Research questions:

- Which color types, bit depths and alpha representations are required by the
  actual consumers?
- Can filtering, interlace handling and CRC failures remain bounded and
  deterministic?
- Which metadata is technical versus presentation/semantic metadata?
- What is the smallest useful Pure-D read/write subset for the editor flows?
- How do encoder filtering/compression choices affect size, speed and exact
  decoded samples? What technical metadata can round-trip without loss?

Admission evidence:

- PNG conformance and malformed corpus;
- independent reference decoder comparison;
- native sample/alpha preservation;
- independent decode of encoded output and exact lossless sample comparison;
- declared metadata preservation/loss and failed-write behavior;
- allocation and throughput measurements;
- explicit consumer need.

## Gate J — JPEG read/write

JPEG is a separate editor-driven format gate, not implied by TIFF or PNG.
Define the exact initial variant subset before implementation (for example,
do not claim progressive or uncommon colour modes from baseline fixtures).

Research questions:

- Which JPEG variants, sample/channel models, orientation/profile/EXIF fields
  and encoder controls are required by the real editor flows?
- How can a Pure-D codec be bounded on malformed or adversarial input while
  reporting unsupported variants instead of silently changing samples?
- What output representation and codec-mandated transforms are explicit, and
  which colour-management decisions remain with `color-d`/`imagery-d`?
- What quality, size, memory and throughput trade-offs are acceptable for
  lossy export and subsequent independent decode?

Admission evidence:

- pinned independent JPEG decode and encode oracles, representative fixtures
  and malformed/unsupported cases;
- declared read and write variant matrix, metadata-loss and partial-write
  contracts;
- decoded-output comparison using a stated lossy metric/tolerance;
- DMD/LDC correctness, bounded memory and consumer-visible performance.

## Gate W — classic TIFF write

The first uncompressed one-strip writer is a research probe, not a general
TIFF write capability. Its DMD/LDC exact-pixel GDAL oracle is under
`experiments/tiff_write/`.

Research questions:

- Which technical sample and metadata fields must survive a scientific-editor
  read/edit/save cycle without silently changing values or semantics?
- When should multi-strip/tiled output, compression and predictor selection be
  exposed, and how does that affect bounded memory and sink failures?
- Is little-endian chunky output sufficient for an initial consumer slice, or
  are planar, BigTIFF and GeoTIFF write separate necessary variants?

Admission evidence:

- independent GDAL/ImageMagick reopened output across each declared variant;
- exact native sample comparison, alpha/metadata retention and explicit loss;
- malformed dimensions, offset/byte-count overflow and short sink tests;
- DMD/LDC memory, throughput, file-size and actual consumer round-trip.

## Gate order

1. Compression, because it extends the current TIFF block path.
2. BigTIFF, because it changes offset width and parser invariants.
3. GeoTIFF metadata, after technical TIFF metadata is stable.
4. COG transport, after source/range/cache contracts are admitted.
5. PNG read/write as a separate editor-driven interoperability track.
6. Classic TIFF write as a separate scientific/editor export track.
7. JPEG read/write as a separate editor-driven format track. The order of
   PNG versus JPEG implementation is decided by real consumer evidence.

No gate creates a public package or stable API by itself.

Current probe status is tracked in `docs/research/FORMAT_GATE_STATUS.md`.
The provisional **next research-effort** queue (not an admission order) is in
`docs/research/NEXT_FORMAT_GATE_PRIORITY.md`; it preserves the dependency
order above while distinguishing editor and scientific-image gaps.

