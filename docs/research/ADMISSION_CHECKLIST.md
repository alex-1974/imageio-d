# Admission checklist — research completion

This checklist defines the remaining end state for the first Pure-D TIFF
research slice. It is not a production release checklist.
The broader read/write product requirements and three target consumers are
tracked separately in ADR 0006 and `CONSUMER_READ_WRITE.md`; completing this
reader-slice checklist alone cannot admit a public imageio-d package.
Real imageio-d consumer integration remains a post-release validation item;
the pre-release gate uses independent public DUB consumers and the complete
read-process-write probe.

## Correctness

- [x] Header and IFD bounds are checked without allocation.
- [x] Technical tag result path exists.
- [x] External LONG arrays have caller-owned output and bounds errors.
- [x] External SHORT arrays have caller-owned output and bounds errors.
- [x] Multi-band `BitsPerSample` preserves external-array identity in the IFD
      result instead of collapsing it to a scalar.
- [x] Interleaved, planar and tiled payload probes exist.
- [x] Strip and tile offset bridges exist.
- [x] Independent TIFF oracle comparison for the complete selected corpus.
- [x] Connect parsed TIFF strip/tile metadata to the Pure-D payload decoder and
      compare decoded ROI bytes against the GDAL raw oracle.
- [x] Independent ImageMagick/GDAL dimension and core-tag comparison for
      external 8-bit, 16-bit and optional tiled fixtures.
- [x] Independent ImageMagick/GDAL technical-shape comparison for an external
      RGB fixture with three `BitsPerSample` values.
- [x] External SHORT-array negative probes cover destination size, truncation
      and both byte orders.
- [x] External RGB fixture has a reproducible GDAL raw pixel-stream oracle.
- [x] Single-strip 8-bit TIFF metadata is connected end-to-end to the
      Pure-D strip decoder and compared byte-for-byte with GDAL raw output.
- [x] Single-strip interleaved RGB TIFF is connected end-to-end and compared
      byte-for-byte with GDAL raw output.
- [x] Single-strip native 16-bit TIFF is connected end-to-end and compared
      byte-for-byte without sample-width reduction.
- [x] Three-plane 8-bit TIFF is connected through external strip arrays and
      the Pure-D planar-to-interleaved decoder against GDAL RGB raw output.
- [x] Tiled 16-bit TIFF is connected through external tile arrays, including
      edge-tile clipping, against GDAL raw output.
- [x] Tiled edge regression proves direct caller-owned output without a
      full-image intermediate buffer.
- [x] Real external fixtures have truncation, byte-order, magic and IFD-offset
      negative probes.
- [x] Tiled output includes an explicit non-origin ROI byte-equivalence check.
- [x] Real planar and tiled fixture oracles compile and pass under DMD and
      LDC.
- [x] Real planar and tiled fixture latency/RSS measurement protocol exists
      for DMD and LDC.
- [x] Repeated real-fixture variance protocol exists without compilation
      overhead.
- [x] 1024×1024 planar and tiled fixture measurement runs under optimized DMD
      and LDC with peak RSS reporting.
- [x] Reproducible external TIFF fixture generation and GDAL inspection.
- [x] Little-/big-endian sample-value oracle for 16-bit and 32-bit values.
- [x] Little-/big-endian header parsing probe.
- [x] Float32 bit-preservation oracle.
- [x] Full negative corpus across the complete selected corpus: overflow,
      overlap, invalid counts and unsupported sample representations.
- [x] Offset-range and overlap validator probe for block descriptors.
- [x] Unsupported sample-width, sample-format and compression rejection probe.

## Ownership and performance

- [x] `@safe @nogc nothrow` parser/result probes.
- [x] Caller-owned destination and explicit strides.
- [x] Multi-strip and tile direct-to-destination traversal.
- [x] Benchmark protects against compiler elimination.
- [x] DMD/LDC optimized baseline recorded.
- [x] Tile-size matrix and edge-tile benchmark.
- [x] Peak-memory and copy-count evidence for the complete selected corpus.
- [x] Copy-count evidence is reported by payload benchmarks.
- [x] Peak-RSS measurement recorded on the baseline host.
- [x] Repeated-run variance on the baseline host; second-host/compiler matrix
      is post-release validation.
- [x] Three-run variance protocol and initial same-host snapshot.

## API and integration

- [x] D-native API sketches.
- [x] Technical versus imagery-semantic boundary probe.
- [x] `raster-d` vocabulary and lifetime direction documented.
- [x] Provisional API shape selected from the consumer-flow probes.
- [x] Metadata crosswalk with `imagery-d` M1/M2.
- [x] Technical-to-imagery crosswalk documented without implicit bindings.
- [x] Isolated consumer materialization-key probe with explicit bindings and
      source revision.
- [x] Real sibling `imagery-d` M2 consumer-contract experiment passes under
      DMD and LDC.
- [x] Explicit decision on research admission and public-API deferral.

## Decision

Admission to the next research stage requires every unchecked item above to
have evidence or an explicit defer/reject decision. The current decision is
recorded in `docs/research/ADMISSION_DECISION.md`: the bounded slice is
accepted for continued research, while public DUB/package/API admission is
explicitly deferred.
