## Goal

Select and validate the first Pure-D format/consumer vertical slice.

## Questions

- [x] Which format has the strongest concrete consumer need and manageable
      Pure-D implementation scope?
- [x] Can the format preserve native samples, bands, metadata and validity?
- [x] Can it support a useful window/tile/scanline path?
- [ ] What are the malformed-input and decompression-bomb limits?
- [x] What independent decoder/reference will serve as the oracle?
- [x] What is the minimum corpus and how are fixtures hashed and reproduced?

## Current research selection

- [x] Select bounded TIFF core as the first research slice.
- [x] Add a header/IFD parsing probe with checked truncation and magic errors.
- [x] Verify the parser probe under DMD and LDC.
- [x] Replace the exception-only parser path with an allocation-free structured
      error/result probe.
- [x] Add and verify an allocation-free structured header result probe.
- [x] Add an allocation-free IFD/tag result parser compile probe.
- [x] Add caller-owned external LONG-array decoding with bounds checks.
- [x] Add caller-owned external SHORT-array decoding for multi-band metadata.
- [x] Preserve multi-band `BitsPerSample` external-array identity in the IFD
      result.
- [x] Add external SHORT-array negative probes for truncation, destination
      size and endian handling.
- [x] Add uncompressed interleaved caller-owned payload decoding with strides.
- [x] Add planar and tiled payload decode probes.
- [x] Add explicit multi-byte sample and Full-Decode/ROI byte-equivalence
      probes.
- [x] Connect checked strip offset/byte-count ranges to the payload decoder.
- [x] Add multi-strip direct-to-destination traversal without a full-image
      intermediate buffer.
- [x] Add tile-offset traversal with edge-tile clipping and direct output.
- [x] Add negative tile-count and tile-range tests.
- [x] Add a reproducible DMD/LDC payload throughput and copied-byte probe.
- [x] Add optimized DMD/LDC matrix cases for sample widths and layouts.
- [x] Add cache-blocked planar-to-interleaved decoding and compare it in the
      optimized benchmark matrix.
- [x] Add a specialized three-band 16-bit planar path and benchmark it.
- [x] Add a tile-size benchmark matrix with edge tiles.
- [x] Add a resource measurement script for copied bytes and peak RSS.
- [x] Add independent 16-/32-bit endian sample-value oracle probes.
- [x] Add block offset-range and overlap negative tests.
- [x] Add unsupported sample representation and compression tests.
- [x] Add external ImageMagick/GDAL fixture generation for oracle comparison.
- [x] Add an internal compiler-specific tile-tuning probe without exposing it
      as public API.
- [x] Correct the benchmark for compiler elimination and record the baseline.
- [x] Complete external tag-array decoding and strip/tile payload fixtures.
- [x] Add reproducible external 8-bit, 16-bit and optional tiled fixtures with
      ImageMagick/GDAL dimension and core-tag comparison.
- [x] Connect external TIFF strip/tile metadata to the Pure-D payload decoder
      and perform byte-for-byte ROI comparison against GDAL raw output.
- [x] Connect the single-strip 8-bit fixture end-to-end and compare its bytes
      against GDAL raw output.
- [x] Connect the three-plane RGB fixture through external LONG `StripOffsets`
      and SHORT `StripByteCounts` arrays to the planar decoder.
- [x] Measure real planar/tiled fixture latency and peak RSS under DMD/LDC.
- [x] Complete planar and tiled payload fixtures with ROI equivalence.
- [x] Measure allocation behaviour and document the `@nogc` boundary.
- [x] Start a separate PNG read/write interoperability probe with DMD/LDC
      independent oracles; Gate P remains open.
- [x] Compare full-staging and row-bounded PNG paths, including a fast stored
      encoder mode and its size/speed trade-off.
- [x] Probe packed/indexed PNG native reads and explicit transparency payload.
- [x] Start separate classic-TIFF write oracle with GDAL.
- [x] Prepare a JPEG seed corpus without claiming a Pure-D JPEG codec.
- [x] Add a bounded Pure-D baseline JPEG 8-bit gray/YCbCr read/write probe
      with independent DMD/LDC Pillow/ImageMagick oracles; Gate J stays open.
- [x] Probe adaptive PNG filtering and conservative same-shape ancillary
      metadata transfer with explicit loss/applicability decisions.
- [x] Compare a temporary bounded hash-chain Pure-D Deflate strategy against
      provider fixed-LZ and stored rows; retain compression-d ownership.
- [ ] Preserve PNG ancillary metadata and qualify Adam7/APNG separately.
- [ ] Implement and qualify Pure-D JPEG baseline read/write.
- [ ] Qualify TIFF write beyond one uncompressed strip.
- [ ] Defer GeoTIFF keys, BigTIFF, compressed TIFF and COG transport to
      separate evidence gates.

## Exit evidence

- [ ] Format specification and licence review.
- [ ] Positive and negative corpus.
- [ ] Differential sample and metadata comparison.
- [ ] Memory, copy, throughput and I/O measurements.
- [ ] DMD/LDC results.
- [x] Explicit accept, defer or reject decision.

The complete remaining gate list is maintained in
`docs/research/ADMISSION_CHECKLIST.md`.
