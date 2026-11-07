# PNG editor gate: technical representation and metadata

Status: 2026-10-28 research evidence, not public PNG support. Normative
reference: [PNG Third Edition](https://www.w3.org/TR/png-3/).

## Current read/write distinction

| Variant | Native read probe | Write probe | Remaining decision |
|---|---|---|---|
| Gray, gray+alpha, RGB, RGBA 8/16-bit non-interlaced | Yes; exact decoded sample bytes | Yes; filter-0/adaptive fixed-LZ or fast stored rows | Size/throughput balance, sink/source lifetime |
| Packed grayscale 1/2/4-bit | Yes; packed row bytes, no scaling | No | Whether editor adapter requests unpacked values |
| Indexed 1/2/4/8-bit | Yes; packed indices plus validated PLTE/tRNS payload | No | Preserve indexed edit/export or explicitly expand with an adapter |
| Truecolour/grayscale `tRNS` | Raw payload reported without implicit alpha synthesis | Separate transfer probe can retain it for same-shape output only with caller applicability assertion | Transparent-key semantics after pixel edits |
| Adam7 | No | No | Separate interlace oracle and row-pass memory bounds |
| APNG | Explicitly rejected when animation chunks are present | No | Consumer need and frame/timing semantics; separate gate |

For indexed samples, the decoder validates that every visible index is within
PLTE. Padding bits in the last byte of each row are retained as technical
bytes. PLTE RGB triples and tRNS bytes are returned separately; the codec
does **not** silently turn them into RGBA or decide an alpha policy for
`imagery-d`. PNG 16-bit samples remain big-endian bytes.

## Metadata-transfer rule to test before admission

The basic writer still uses `rejectLoss` by default and requires explicit
`drop`. A separate caller-owned `encodePngWithMetadata` experiment now copies
safe-to-copy ancillary chunks (including text and unknown safe chunks) around
new IDAT data, retaining their pre-/post-IDAT side and byte content. Known
colour/transparency chunks (`PLTE`, `tRNS`, `iCCP`, `sRGB`, `gAMA`, `cHRM`,
`sBIT`) are copied only if the caller attests they remain applicable and the
output shape matches. Unknown unsafe-to-copy chunks, including EXIF in this
probe, fail closed unless the caller explicitly permits dropping them. The
DMD/LDC tests cover unknown safe chunks before/after IDAT, unsafe rejection
and explicit drop, and `gAMA` opt-in; Pillow independently reopens the result.
This is byte retention, not semantic validation or metadata rewriting.

The [PNG editing rules](https://www.w3.org/TR/png-3/) govern
safe-to-copy and ordering; the probe only implements the subset described
above. `color-d` remains responsible for colour
mathematics and `imagery-d` for image semantics; `imageio-d` may report and
transport technical profile/chunk data without performing colour management.

## Next evidence

- Read- and write-side packed/indexed editor flow with explicit representation
  choice, no implicit palette expansion and a separate independent oracle.
- Expand metadata oracles to recognized ICC/EXIF content, chunk-specific
  ordering/multiplicity and actual pixel edits. The current transfer is a
  same-shape byte-retention experiment, not a semantic editor contract.
- Adam7 and APNG kept separate; do not infer support from non-interlaced PNG.
- Chunked source reads and a transactional or explicitly partial sink wrapper.
  `decodePngRows` currently receives a full file slice. `StoredRowWriter`
  emits a complete chunk per row, but sink failure/cleanup belongs to the
  caller and cannot be rolled back by the codec.
