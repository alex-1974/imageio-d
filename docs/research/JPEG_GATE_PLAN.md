# JPEG read/write gate — first variant and oracle plan

Status: 2026-10-28 research only. A bounded Pure-D JPEG baseline codec
**experiment** now exists under `experiments/jpeg_gate/source/`, not a public
package/API. `experiments/jpeg_gate/check.sh` checks the corpus under DMD/LDC
with Pillow 12.3.0 and ImageMagick 7.1.2-31. The
Pillow/ImageMagick decoded outputs of the current tiny corpus happen to be
byte-identical; this is not a general JPEG tolerance or codec validation.
The baseline-RGB fixture SHA-256 is
`7411e0dd987a3ff4ed654527b331df1d524e650a360b963734b7d6ca4c90140a`;
the EXIF/ICC fixture's normalized hash is
`783ce7fce7ba81de4133ea059cea0fe0726ee1d90cef528298fde8cca2fd5a19`.

## Proposed first read subset

- Baseline sequential 8-bit grayscale and three-component YCbCr/JPEG, decoded
  to an explicitly requested technical representation. Marker order, scan
  boundaries, dimensions, Huffman table validity, restart intervals and
  resource limits require negative tests.
- No silent orientation, ICC or EXIF application. Report these fields or
  explicitly refuse to preserve them; colour-management decisions remain in
  `color-d`/application policy, not hidden in decoder output.
- Progressive, arithmetic, CMYK/YCCK, 12-bit, lossless JPEG, MPO and JPEG XL
  are not implied by a baseline result. Each needs a separate decision.

## Proposed first write subset

- Baseline sequential 8-bit grayscale and explicitly identified JFIF/YCbCr
  components with quality, subsampling and metadata-loss policy. The current
  RGB-derived experiment uses a convenience conversion, but a public
  format-core API must not own generic RGB/YCbCr colour mathematics. Native
  components and an explicit `color-d`/application adapter are the research
  direction in `JPEG_COLOR_BOUNDARY.md`.
- Independent reopen of each encoded output, dimensions/channel checks,
  declared lossy metric (per-channel error distribution, PSNR/SSIM where
  justified), size and throughput. Byte equality with input is not expected.
- Partial write and destination ownership must be explicit before a file or
  caller-sink API is considered stable.

## Current gate evidence and blockers

The Pure-D decoder parses marker/DQT/DHT/SOF0/SOS/DRI/RST, canonical Huffman entropy,
dequantization, IDCT and YCbCr conversion. It passes Pillow-generated baseline
gray/RGB 4:4:4/4:2:2/4:2:0 and EXIF/ICC-bearing 4:4:4 files under DMD/LDC.
4:4:4 maximum per-channel delta from Pillow is 1 gray / 2 RGB; subsampled
decodes differ at MCU edges (max 50 for 4:2:2, 41 for 4:2:0; mean below 2).
Progressive, CMYK, truncated, zero-quantizer, invalid-Huffman and Adobe
raw-RGB markers are rejected. These are a small negative corpus, not a
comprehensive security validation.

The Pure-D encoder writes baseline 8-bit gray or RGB-derived YCbCr
4:4:4/4:2:2/4:2:0, with explicit quality 1–100 (default 75), separate
luma/chroma quantizers, configurable restart interval, canonical but
deliberately non-optimal Huffman tables and caller-owned output. Supplied EXIF
APP1/ICC APP2 metadata defaults to rejection; opt-in copy and explicit discard
are tested, including two-segment ICC reassembly by Pillow. This is opaque
metadata transport, not colour management or orientation application. Invalid
quality values 0/101, malformed metadata and undersized output are rejected
without writes.
The separate `inspectJpegMetadata` probe reports borrowed EXIF offsets and
ordered ICC segment offsets without allocating or interpreting the payload.
It rejects duplicate ICC sequence numbers and too-small caller span. Pixel
decoding does not silently invoke this scanner or promise metadata retention.
Both Pillow and ImageMagick independently reopen DMD/LDC outputs at quality
1/30/75/95/100; matching DMD/LDC output bytes are checked. A quality-100
RGB case exposed a 16-zero-run (ZRL) decoder bug; the fixed regression passes.
The quantizer now clips high-quality AC coefficients to the baseline 10-bit
amplitude range.

For the 19×11 raw patterns, at quality 95 the output is 851 bytes gray /
1,364 bytes RGB, with independent decoded max error 5 / 14 and mean error
0.78 / 1.35. At quality 100, output is 929 / 1,698 bytes, max error 1 / 3
and mean error 0.07 / 0.19. At quality 30, RGB mean error is 18.38 and its
maximum is 190; the quality scale is not a target error bound. These values
are tiny-fixture evidence, **not** a general encoder quality, size or
throughput guarantee.

The expanded release-build oracle passes 1×1 gray, 17×19 high-contrast RGB,
257×193 gradient RGB and 256×256 high-frequency RGB with restart-marker
rotation, independent Pillow/ImageMagick decode and byte-identical DMD/LDC
output. On the high-contrast 17×19 4:2:0 case, mean error versus source is
57.51 and maximum 167; on 256×256 4:4:4 texture, mean is 3.20 and maximum
23. Subsampling is therefore a visible lossy choice, not a free size win.
The earlier MCU-local decoder differed from Pillow by as much as 64 on the
17×19 edge pattern and 98 on the 257×193 gradient. A whole-image post-pass
now interpolates across MCU boundaries using two fixed, `@nogc` chroma row
buffers in caller-owned destination storage. The same 4:2:0 cases now differ
by at most 2 and 3 respectively; an additional 17×19 4:2:2 edge case differs
by at most 2. Padded-stride and destination-canary regressions pass under DMD
and LDC. A 1×19 4:2:0 case differs by up to 27 because the independent
libjpeg-turbo oracle switches to nearest-neighbour upsampling when the
downsampled width is at most two; this probe keeps 3:1 interpolation.
The [libjpeg-turbo upsampler selection](https://fuchsia.googlesource.com/third_party/libjpeg-turbo/+/eb7962a02b749f3185e9970bb07c9f7c86b85d73/jdsample.c)
supports that interpretation. This closes the *known MCU-boundary defect* for
the bounded synthetic corpus, not the broader image-quality gate.
The small corpus also probes 2,088 deterministic byte flips/truncations per
compiler with destination canaries. A release-only Huffman initialization bug
was found and fixed; the release corpus now guards it.

The FDCT/IDCT were changed to separable transforms and encoder Huffman lookup
to direct codes. The earlier single-image timing was too narrow and varied
markedly between repeats. It is superseded by the paired four-case DMD/LDC/
Pillow runner in `experiments/jpeg_gate/bench.sh`; the protocol, preflight and
limitations are in `JPEG_BENCHMARK_METHOD.md`. The runner records host,
compiler, fixture and source identity; exact-input decode, individual rounds,
variability, output size and correctness metrics. It still exposes a material
Pure-D/Pillow throughput gap on synthetic workloads, but different allocation,
entropy and sample-quality contracts prevent a like-for-like speed or size
claim. After cross-MCU interpolation, the 4:2:0 same-file decode differs from
Pillow by at most three levels on the benchmark fixture. This is a tolerance
result, not byte-identical output or proof for real photographs. A small
hash-pinned photographic corpus (CC0 landscape, NASA Earth view and a Pillow
test fixture with unverified image-specific redistribution terms) now probes
the baseline conversion of independent pixels. Profiling identified the
bit-at-a-time entropy writer as one encode hotspot; a packed bitwriter is
byte-identical to its LDC legacy variant on the tested sources and has
directionally favorable paired results on the landscape and flower. The Earth
results vary between runs, so no universal speedup is claimed. With the earlier
floating colour surrogate, DMD/LDC encoded bytes differed on the landscape,
though independent decoded pixels differed by max 4 and mean 0.00054; exact
compiler equality is not a general property.
CPU affinity and sampled clock values are recorded, but the `powersave`
governor remains uncontrolled.
There is **no stable consumer performance baseline or gate pass yet**.

The 2026-10-29 compiler diagnosis localizes that historical landscape
divergence: 104 RGB→YCbCr sample bytes differed, followed by 13 quantized
coefficients, and **none** of the differing coefficients came from blocks with
equal input samples. A Q16 integer conversion in the internal surrogate now
produces identical samples, coefficients and JPEG bytes under DMD/LDC on the
pinned landscape. The same integer output is byte-identical across both
compilers in all 12 real-content quality/sampling cases tested; this is not a
universal compiler guarantee. It changes the decoded landscape output by at
most 8 levels versus the old float surrogate (mean absolute difference
0.00159, PSNR versus raw 41.4518 versus 41.4515 dB). The cause of the
floating evaluation difference below the sample-rounding boundary was not
isolated to a specific compiler operation. The Q16 transform belongs only to
this oracle surrogate, not to an admitted image-I/O colour API.

The real-content corpus now exercises three hash-pinned images × quality
30/90/100 in 4:2:0 and quality 90 in 4:4:4. Pillow and ImageMagick reopen
all outputs; the same-file D decode differs from Pillow by at most three
levels in all 12 variants under both compilers. A 64-position byte-mutation
and eight-prefix truncation canary sweep per image/compiler completed, with
some mutations still valid and accepted. This is broader bounded evidence,
not a malformed-file security corpus or fuzzing pass. The benchmark preflight
now **fails** rather than merely reports if same-file decode exceeds its
three-level research tolerance. That check caught an experimental sparse-IDCT
bug: D's floating array `.init` is not zero, so the accumulator needed an
explicit zero fill before conditional additions. The corrected sparse path
retains the tested oracle tolerance. See `JPEG_BENCHMARK_METHOD.md` for the
paired timing limits and `JPEG_SOURCE_SINK_CONTRACT.md` for unresolved I/O
semantics.
On the landscape, D output PSNR versus source is 29.32 dB at quality 30
4:2:0, 41.45 dB at quality 90 4:2:0, and 43.22 dB at quality 90 4:4:4.
These are content- and policy-specific measurements, not quality guarantees.

The gate remains open: broader chroma/image-quality evidence, a large
independently sourced malformed/security corpus (the ten pinned external
invalid JPEGs in `external_malformed.sh` only establish a smoke test),
optimized entropy coding and DCT beyond the current separable form, a
source/sink/partial-write API, complete metadata-loss reporting on read,
representative performance across image classes,
and actual consumer workflows. Decoding can leave partial rows in the
destination on a later entropy error; a failed result currently makes those
bytes unspecified. None of the above admits a public JPEG format claim.

The 2026-10-29 native-plane probe separately encodes and decodes gray and
YCbCr component planes under DMD/LDC without implicit colour conversion,
including 4:4:4/4:2:2/4:2:0 odd dimensions, padded strides and canaries.
Pillow and ImageMagick reopen all four variants. A pre-scan inspector reports raw component
IDs, sampling and JFIF/Adobe/unknown signalling; the legacy RGB read now
rejects ambiguous and Adobe-raw-RGB streams. A separate fixed-window
source/sink experiment exercises short reads/writes, backpressure, retry,
partial file, cancellation and explicit accepted-byte counts; it is not
incremental JPEG. Successful encode reports copied/discarded metadata. The
audited native-plane reader preflights EXIF/ICC and counts unrecognized
APP/COM payloads, requiring explicit report or discard before decoding;
malformed ICC and short metadata descriptors fail before pixel writes.
Non-default JFIF/Adobe fields are now counted as loss risks, but their values,
arbitrary opaque payloads and semantic preservation remain outside that narrow
read audit. The
ten independent malformed seeds pass both compilers with canaries, but this
does not close the security gate. The latest paired IDCT run is mixed and
drift-sensitive, so dense IDCT remains default; see
`JPEG_BENCHMARK_METHOD.md`. All four tracks remain research, not admission.

The subsequent native-plane read–modify–write surrogate audits metadata
before decoding, changes one luma sample without RGB conversion, then saves
with explicit EXIF/ICC copy and explicit discard. Independent Pillow and
ImageMagick reopen both outputs; Pillow checks retained versus absent EXIF/ICC.
The test covers a Pillow-source single-segment ICC and a two-segment ICC
source emitted by the probe. It runs under DMD/LDC and compares output bytes.
This is a technical format-core exercise, **not** a real `raster-d`,
`imagery-d`, `color-d` or editor consumer, and it does not preserve every
possible APP marker or non-default JFIF density/thumbnail field.

A subsequent fixed-state, pull-based header scanner now advances through SOS
without seeking or buffering the whole encoded JPEG. It handles short reads,
backpressure and an oversized split-ICC APP2 header, and explicitly returns
prefetched bytes for entropy hand-off. DMD/LDC tests exercise truncation at
every short-header prefix, source failure and malformed pull responses.
The initial probe proves bounded incremental **header inspection** with a
simulated short-read source. A follow-up Linux probe exercises it on a
real nonblocking OS pipe, including repeated pauses, early EOF and exact
pending-byte/pipe-suffix hand-off for baseline and split-ICC files. The
fixture producer remains prebuffered. DQT/DHT contents, ICC/EXIF policy,
entropy and pixels still require the prebuffered codec paths; a real
streaming pixel decoder has not been demonstrated. See
`JPEG_SOURCE_SINK_CONTRACT.md` for the byte-accounting contract.
