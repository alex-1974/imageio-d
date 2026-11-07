# Pure-D PNG read/write research slice

This is a local experiment, not a public imageio-d package or API. The
experiment-local DUB package depends on the local Pure-D `compression-d`
checkout. `compression-d` already supplies `inflateZlib`, `encodeZlibStored`,
the size helper and CRC-32; no native codec backend is linked.

## Deliberate subset and ownership

- PNG signature, checked chunks and CRC, IHDR/IDAT/IEND ordering, split IDAT,
  bounded zlib inflate, filters 0–4, and 8-/16-bit gray, gray+alpha, RGB and
  RGBA non-interlaced samples. Read-only native packed grayscale 1/2/4-bit and
  indexed 1/2/4/8-bit cases expose PLTE/tRNS separately and validate indices.
- 16-bit samples are delivered/stored as PNG big-endian bytes; there is no
  implicit host-endian conversion, colour management, band binding or alpha
  policy. A caller owns input, output, compressed/filtered scratch and the
  `InflateWorkspace`; separate concurrent calls need disjoint storage.
- The original encoder uses filter 0 or adaptive row filters and
  `compression-d` fixed-LZ zlib in one IDAT chunk. The faster research path
  now calls `compression-d`'s caller-owned `HashChainMatchFinder` and raw
  fixed-Huffman encoder. The fast research API takes a `ref` finder, so callers
  can own it on the stack without a GC allocation. This experiment adds only
  the zlib header and Adler-32 trailer because the provider has no hash-chain
  zlib one-shot API.
  The superseded local codec prototype is preserved in `archive/`, outside
  the active build path. Compression ownership remains with `compression-d`.
  A speed-oriented stored-block variant uses one row of scratch;
  `StoredRowWriter` accepts one caller row and emits one IDAT chunk per call.
  Neither is a production-quality size/speed default.
- The reader reports ancillary presence and retains PLTE/tRNS through
  caller-owned extraction buffers. The basic writer rejects metadata loss by default
  (`rejectLoss`) or drops it only with explicit `MetadataPolicy.drop`,
  reporting `metadataDropped`. A separate same-shape transfer probe preserves
  safe chunks and opt-in known colour chunks, rejecting unsafe unknowns unless
  explicitly dropped. No silent transparency interpretation.
- Packed/indexed **write**, Adam7, APNG, complete semantic metadata round-trip,
  file-source streaming and pixel-strided views are unsupported. Technical
  inspection still scans and checks every chunk/CRC; it does not inflate
  pixels. Unknown critical chunks are rejected.

The default limits cap pixel count, decoded/filtered bytes, compressed bytes,
encoded file bytes and cumulative ancillary payload. Caller-provided buffers
are preflighted before destination pixels are
written. Decode validates and unfilters the full image in scratch before
committing rows; write stages filtered and compressed data before emitting
output. This original path requires full-image scratch plus compressed staging.
`decodePngRows` consumes IDAT slices with two row buffers and may leave
complete earlier rows visible on codec/filter failure; `written` reports
committed sample bytes. Its input remains a complete PNG byte slice.
`StoredRowWriter` produces output chunks for a caller sink, whose prior writes
cannot be rolled back. Inputs, scratch and destinations must not alias. These
are research contracts, not admitted public guarantees.

## Independent oracle

Run from this directory against the declared local DUB path dependency:

```sh
sh check.sh
```

To verify a specific, separately checked-out `compression-d` revision without
switching the active provider branch, set `COMPRESSION_D_ROOT` to that
checkout's absolute path. In this mode the script compiles and fully links
the selected provider with the PNG consumer under `-dip1000` and runs the
same independent oracles; the DUB build is intentionally skipped because its
manifest still points at the normal local checkout:

```sh
COMPRESSION_D_ROOT=/absolute/path/to/compression-d sh check.sh
COMPRESSION_D_ROOT=/absolute/path/to/compression-d sh bench.sh
```

The default checker also runs the DUB build and then executes its oracle
against a fully linked `-dip1000` binary of the same local provider.

The script generates deterministic PNGs and raw samples with Pillow,
ImageMagick and Python zlib, then compiles/runs the D decoder and encoder under
DMD and LDC. Both the source PNGs and D-produced PNGs are decoded by the
external oracles and compared byte-for-byte with raw sample fixtures. The
corpus covers all five filters (including IDAT splits across zlib header and
trailer), RGB/RGBA and 16-bit cases, row padding, metadata-loss policy, CRC,
ordering, unknown safe/unsafe metadata transfer, random and one-pixel cases,
indexed/packed native reads, unsupported interlaced/critical chunks,
invalid filter,
truncation, short workspaces and short destinations. SHA-256 fixture hashes
and oracle versions are printed by the script.

The linked `png_api_probe.d` checks the technical, caller-owned
read/write signatures, including the provider match-finder path, under
`@safe pure nothrow @nogc`. It does not import
or validate the real `raster-d`, `color-d`, `imagery-d` or application APIs;
that integration remains deferred. An API-fit assessment is in
`../../docs/research/READ_WRITE_API_BOUNDARY.md`.

`sh bench.sh` records an optimized DMD/LDC small-image baseline. The provider
fixed-LZ path is slow, stored rows trade file size for speed, and the
provider hash-chain path explores the middle. Measurements and the
fully linked DIP1000 gate results are in
`../../docs/research/PNG_RW_BASELINE.md`; metadata/interlace gaps are in
`../../docs/research/PNG_EDITOR_GATE.md`.
