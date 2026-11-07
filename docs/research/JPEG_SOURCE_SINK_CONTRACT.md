# JPEG source/sink and failure contract (research sketch)

Status: design questions, not accepted names, modules or public API.

The current JPEG probe borrows a complete encoded byte slice and writes into
caller-owned memory. It is useful for codec correctness and `@nogc` kernels,
but it does not prove a file, stream or resumable sink interface. In
particular, `encodeJpeg` preflights a conservative *whole-output capacity* and
cannot itself recover a file after a partial write. `decodeJpeg` may leave
partially written pixels when a later entropy error occurs; a failure makes
the destination contents unspecified even though surrounding canaries remain
protected in the tested corpus.

`jpeg_io_probe.d` now tests a separate `@safe nothrow @nogc` fixed-17-byte
transfer state between short-reading and short-writing endpoints. It records
accepted bytes and differentiates backpressure, source truncation/error,
sink error and cancellation. A one-byte-at-a-time transfer, a blocked-and-
resumed transfer, a 12-byte source failure, an 11-byte sink failure and a
truncated source pass under DMD/LDC; the partial file is 11 bytes and is never
reported as complete. Additional sink failures immediately after SOI and
immediately before/inside EOI preserve exact accepted counts and canaries.
This is **not** incremental JPEG entropy decoding or
encoding: the test source and encoded output are prebuffered. The expected
length comes from outer framing, so it cannot itself prove an unknown-length
JPEG source complete. The experiment supplies a failure contract, not a
production streaming adapter or atomic file-save implementation.
The encode experiment now returns `MetadataDisposition` (`none`, `copied`,
`discarded`) on success, and the existing metadata oracle verifies copy and
discard. A native-plane `decodeJpegPlanesAudited` preflight now either rejects
known EXIF/ICC and other APP/COM payloads before touching pixels, reports
their borrowed EXIF/ICC offsets and opaque-marker counts, or records explicit
discard. The DMD/LDC oracle covers absent metadata, one- and two-segment
ICC, short descriptor storage, damaged ICC sequencing, injected APP3/COM
markers, changed JFIF density and Adobe APP14. Non-default JFIF and any Adobe
marker are counted as container-loss risks before decode. Their fields and
opaque APP/COM bytes are not returned for copying. This is a bounded research
policy, not complete metadata preservation or a semantic JFIF/Adobe parser.
Atomic file replacement and an actual incremental codec remain open.
The small native-plane read–modify–write surrogate now exercises an explicit
report → one-sample edit → copy/discard hand-off for EXIF and ICC. Its inputs
and outputs are fully buffered, and it does not establish file atomicity,
`raster-d` storage integration or an application save policy.

`jpeg_stream_header.d` adds a separate, genuinely pull-based **header-only**
experiment. A source needs only `pull(ubyte[])` and may short-read, pause or
fail; it need not seek or provide the complete JPEG in memory. The parser
retains a fixed state (`HeaderState.sizeof <= 256`), uses a 17-byte pull window
and a 32-byte segment prefix, and skips even a two-segment, 70 kB ICC payload
without allocating. It scans SOI through the SOS header, checks baseline SOF0
geometry/component sampling and SOS shape, and reports JFIF/Adobe component
signals. `blocked` can be resumed. EOF during the header, source failure,
unsupported variant, invalid header, cancellation and resource limit have
distinct results. `bytesConsumed` is the exact header length; `bytesPulled`
may be up to 16 bytes ahead. Before handing the source to a subsequent
entropy reader, the caller must take `copyPending` bytes first and then read
from the source. Otherwise prefetched entropy bytes would be lost.

The DMD/LDC probe compares scanner results to the existing slice inspector,
tests one- and two-byte reads, all short-file prefixes, injected errors,
pause/resume, cancellation and malformed pull replies. A separate **Linux**
probe now reads from a real nonblocking, non-seekable OS pipe with interleaved
producer writes. It checks repeated `blocked`/resume transitions, early EOF,
an invalid descriptor and exact reconstruction of the post-SOS suffix from
pending bytes followed by unread pipe bytes. The same probe covers a baseline
JPEG and a 70 kB split-ICC JPEG under both compilers. Its producer still loads
each fixture into memory; it proves the parser/source hand-off, not bounded
end-to-end application memory or a socket/Windows adapter.
On the current 19×11 fixtures, the pipe probe consumed 623 of 1,044 bytes
(4 pauses, 16 pending) and 70,573 of 71,436 bytes for split ICC (140 pauses,
4 pending), identically under DMD and LDC. These are fixture observations,
not an API or performance bound.

The scanner neither validates DQT/DHT payloads nor EXIF/ICC semantics,
decodes entropy or pixels, enforces a total-file limit, or audits metadata
loss. The one-megabyte default budget bounds *consumed header bytes*, not
prefetched bytes or the remaining JPEG. The codec still needs a compatible
incremental entropy path before streaming read can be claimed; output
streaming and atomic save remain separate work.

## Candidate contract to test

- A source is borrowed for the duration of an operation. Sequential JPEG
  decoding should not require seekability; source errors, EOF/truncation and
  unsupported variants must remain distinguishable. Header inspection does
  not allocate or decode pixels. A source adapter may own a file descriptor,
  but the codec must not silently retain it.
- A destination view is caller-owned (`raster-d` storage/lease in a future
  consumer). Its technical component layout and row/pixel strides are
  explicit. Native component planes and any requested colour conversion are
  separate; see `JPEG_COLOR_BOUNDARY.md`.
- An output sink reports the **number of bytes accepted**, not just a
  success boolean. A zero-byte acceptance or short acceptance must have an
  explicit retry/backpressure rule. Once an unrecoverable sink error occurs,
  the encoder is poisoned and reports accepted bytes plus an error; it must
  not claim a complete JPEG without a committed EOI.
- File-level atomicity belongs to an explicit application/file adapter
  (temporary file plus replacement policy). An arbitrary stream cannot roll
  back. Metadata copied, discarded and unsupported must be reported, not
  inferred from successful pixel encoding.
- Cancellation and resource ceilings must be testable at bounded points.
  Full-source and full-output buffering are valid *declared* research paths,
  not a hidden implementation of streaming.

## Required negative probes before choosing a shape

Test short writes at more marker/entropy boundaries beyond the current
one-byte and SOI/EOI probes; zero writes, delayed sink failure, retry after backpressure,
cancellation, source EOF in each segment, malicious length/dimension fields,
and destination canaries on a genuinely incremental codec path.
Record bytes accepted, complete-row/pixel count where meaningful, metadata
loss, ownership and maximum resident memory. Test both DMD and LDC and a
real consumer-shaped read-process-write path. Do not interpret the bounded
mutation sweep as a fuzz/security certification.

No production streaming adapter is admitted merely because these contracts
are written. The M5 consumer and API-fit gates remain open.
