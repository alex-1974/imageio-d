# JPEG research benchmark protocol

Status: diagnostic experiment only. No public JPEG codec, performance promise,
release baseline or admission decision follows from these measurements.

Run from this repository root:

```sh
sh experiments/jpeg_gate/bench.sh --rounds 5 --output /tmp/imageio-jpeg-benchmark.json
# Optional, if CPU 0 belongs to the process affinity mask:
sh experiments/jpeg_gate/bench.sh --rounds 5 --cpu 0 --output /tmp/imageio-jpeg-benchmark-pinned.json
```

Dependencies: `python3`, Pillow, `dmd`, `ldc2`, ImageMagick's `magick`, and
`/usr/bin/time`. At least three paired rounds are required. The JSON includes
the current Git HEAD and dirty flag, SHA-256 hashes of the probe sources,
benchmark driver, runner and compiler binaries, exact compiler commands and
versions, Pillow/libjpeg versions, CPU model, governor and affinity, fixture
hashes, individual paired rounds, median/min/p10/p90/max, relative spread,
encoded size, decode checksum and peak RSS for each isolated D process.
`--cpu` pins execution, but does **not** lock clock frequency; the runner now
records frequency snapshots before/after each sample. This host's `powersave`
governor cannot be described as controlled frequency.

## Workloads and timing boundary

All fixtures are deterministic generated pixels at quality 90:

| Case | Pixels | Mode | Sampling |
| --- | ---: | --- | --- |
| `gray-gradient` | 512×512 | grayscale | 4:4:4 |
| `rgb-smooth` | 1024×1024 | RGB | 4:4:4 |
| `rgb-texture` | 512×512 | RGB | 4:4:4 |
| `rgb-smooth-420` | 1024×1024 | RGB | 4:2:0 |

Optional real-content cases are `real-flower-420` (480×360),
`real-landscape-420` (1600×1200), and `real-earth-420` (1280×852). Their
source URLs, source SHA-256 and licence/provenance notes are pinned in
`benchmark_suite.py`. The landscape is CC0 from Wikimedia Commons; the Earth
view is NASA public-domain material. The Pillow flower is a test fixture whose
image-specific redistribution terms have not been independently verified;
do not redistribute it on the strength of Pillow's software licence. The
original landscape JPEG is progressive, so the runner decodes its pixels with
Pillow and makes a **new baseline JPEG** for the common decode input. That
measures real photographic content within this probe's supported variant, not
the original file's progressive decode. Source hashes are checked before use.

```sh
sh experiments/jpeg_gate/bench.sh --case real-landscape-420 \
  --rounds 5 --inner-repeats 3 --cpu 0 \
  --output /tmp/imageio-jpeg-landscape.json
# --corpus-dir /tmp reads imageio-landscape.jpg instead of downloading it.
```

Every backend receives the same raw pixels for encoding. Each backend decodes
the *identical* JPEG produced once by Pillow for that case. A warm encode and
decode precede each timed sample. Case and backend order rotate between paired
rounds. D timing surrounds one `encodeJpeg` or `decodeJpeg` call only; inputs
and output arrays are allocated beforehand. Pillow timing surrounds
`Image.save(BytesIO)` or `Image.open(BytesIO).tobytes`, which allocate. Process
startup, compilation, fixture creation, file I/O, checksums and oracle checks
are outside the timed region. D memory is whole-process peak RSS and includes
preallocated output; Python RSS is deliberately omitted because the Python
orchestrator retains all fixtures.

The preflight verifies D JPEG dimensions/mode with Pillow, checks that
ImageMagick can decode the D output, compares DMD/LDC encoded byte hashes,
checks decoded byte lengths and checksums, and reports pixel-error metrics
against the original and between D/Pillow decodes of the same JPEG. These
checks reject broken benchmark runs: a same-file D/Pillow decoded-channel
delta above three now aborts preflight, while accepted smaller differences
are still reported rather than called byte-equivalent. This hard check caught
an experimental sparse-IDCT accumulator bug on real photos. The runner retains
the DMD/LDC byte-equality flag and allows only a bounded decoded-pixel/size
difference. The historical floating RGB→YCbCr path differed on the pinned
landscape (cross-compiler decoded maximum 4, mean 0.00054); the Q16 internal
surrogate now yields byte equality on the tested corpus. Neither is a blanket
compiler-independent guarantee.

`--profile` compiles a separate symbolized LDC binary and samples encode and
decode independently with `perf record --no-inherit`; sampled shares explain
where time goes, not wall-clock performance. `--compare-bitwriter` compiles a
legacy bit-at-a-time variant and alternates it with the packed candidate in
the same paired rounds, retaining a Pillow control and byte-equality check.
`--compare-color-transform` pairs the Q16 integer surrogate with the old
floating version; `--compare-idct` pairs sparse and dense IDCT. The unchanged
D operation (decode for colour/bitwriter, encode for IDCT) is retained as a
drift-sensitive control in each pair. The variants' changed output semantics
are reported separately; timing ratios alone do not establish equivalence.
`--workdir` keeps a new diagnostic build directory on failure; omit it for
automatic temporary cleanup.

`diagnose_compilers.py` records the first differing encoder sample and
quantized coefficient by MCU, plus total counts and JPEG hashes under DMD/LDC.
`corpus_gate.py` tests three hash-pinned photographs under four quality/
sampling settings, independently reopens the D files and runs a bounded
mutation/truncation canary sweep. Run offline with `--corpus-dir /tmp` when the
pinned source files are present. These are research oracles, not a malformed
security corpus or production acceptance suite.

```sh
python3 experiments/jpeg_gate/diagnose_compilers.py --float-color \
  --corpus-dir /tmp --output /tmp/imageio-jpeg-compiler-float.json
python3 experiments/jpeg_gate/diagnose_compilers.py \
  --corpus-dir /tmp --output /tmp/imageio-jpeg-compiler-integer.json
python3 experiments/jpeg_gate/corpus_gate.py --corpus-dir /tmp \
  --output /tmp/imageio-jpeg-real-corpus-gate.json
sh experiments/jpeg_gate/bench.sh --case real-landscape-420 --rounds 7 \
  --inner-repeats 3 --cpu 0 --corpus-dir /tmp --compare-idct \
  --output /tmp/imageio-jpeg-idct-paired.json
```

Omit `--corpus-dir` to fetch the pinned images online; the runner checks
their SHA-256 before use. `/tmp` is only an example location, not a durable
evidence archive. Keep the JSON record with the corresponding source state
when making a future gate decision.

## Reading the result

Compare absolute distributions and paired rounds first. A relative min–max
spread above 20% is flagged as unstable. The D/Pillow time and file-size
ratios are *directional diagnostics*: different entropy/rounding decisions,
output lengths, memory-allocation contracts and decode sample values make them
unsuitable for a language-level or release-performance claim. The report
marks same-file sample tolerance against Pillow at a maximum per-channel
difference of three levels. This is a narrow oracle tolerance, not byte
identity or a guarantee on a representative image corpus. A speed ratio is
not an acceptance criterion merely because this tolerance passes.

The default generated corpus is intentionally small and synthetic. The
optional three-photo corpus adds real content but still does not represent
editor workloads, satellite products, metadata-heavy files, independently
sourced malformed/adversarial inputs or streaming sources/sinks. For
qualification, retain an independently sourced, licensed real-world corpus,
equivalent validation/quality policy and comparable allocation/ownership
contracts; measure consumer-representative read/write workflows on controlled
hosts with repeated baseline/candidate runs. Investigate materially comparable
gaps and retain the accepted evidence per `.workspace/QUALITY_GATES.md` §7.

## Local diagnostic snapshot, 2026-10-28

Five paired rounds on Intel i7-9750H, CPU 0 affinity, `powersave` governor;
DMD 2.111.0, LDC 1.42.0, Pillow 12.3.0 with libjpeg-turbo. Source tree was
dirty, so Git HEAD `e6fa00f` alone is **not** the measured code identity; the
machine-readable record includes source and binary hashes. Medians in ms:

| Case | LDC encode / decode | Pillow encode / decode | LDC encode-size ratio | Same-file decode max delta |
| --- | ---: | ---: | ---: | ---: |
| gray-gradient | 9.546 / 5.143 | 0.505 / 0.450 | 1.456 | 0 |
| rgb-smooth | 134.978 / 161.669 | 5.193 / 5.841 | 1.687 | 3 |
| rgb-texture | 83.919 / 80.698 | 2.931 / 4.593 | 1.965 | 3 |
| rgb-smooth-420 | 93.192 / 136.850 | 3.170 / 4.290 | 1.592 | 75 |

The LDC encode relative min–max spread ranged from 37% to 42%; gray decode
spread was 66%. These figures establish a throughput investigation, not a
stable point estimate or a claim that the two libraries do identical work.
That 4:2:0 pixel delta was a correctness/quality gate before performance claims;
the cross-MCU post-pass now reduces it on the same synthetic fixture.

## Local diagnostic snapshot after cross-MCU fix, 2026-10-28

The latest five-round host setup (including representative-only chroma staging)
yielded LDC 4:2:0 encode/decode medians of 84.177 / 82.692 ms and Pillow
3.002 / 3.882 ms. The maximum same-file decode difference dropped from 75 to
3. Other cases also moved substantially between runs (gray decode relative
spread was 177% in this run and exceeded 400% in an earlier post-fix run), so
the apparent timing changes are **not** evidence of a speedup caused by the
fix. The quality improvement is independently covered by stress/corpus
assertions.

## Packed bitwriter investigation, 2026-10-28

With 5 inner repetitions per round on the pinned flower fixture, LDC encode
medians were 11.265 ms packed versus 16.592 ms legacy; packed won 6 of 7
pairs. On the CC0 landscape (3 inner repetitions), medians were 167.874 ms
versus 174.557 ms and packed won all 5 pairs. On the NASA Earth view (5 inner
repetitions), medians were 79.453 ms versus 86.795 ms and packed won 6 of 9
pairs; an earlier five-round run on that image had a *slower* packed median.
Pillow control and per-invocation CPU-frequency snapshots are retained in the
JSON. These are directional, drift-sensitive results, not a universal speedup
claim or a release threshold. Both LDC variants produced byte-identical JPEGs
for each tested source; DMD/LDC equality is a separate question.

The separate `perf` sample on the flower content attributed about 22% of
pre-change encode samples to `emitSymbol`, with the bit-at-a-time writer
inlined there. The packed version shifts that cost; this is mechanism
evidence, not a substitute for paired wall-clock results. Decode remained
dominated by IDCT and chroma conversion, which this change does not target.

## Compiler and IDCT investigation, 2026-10-29

The reproducible compiler trace on the pinned CC0 landscape finds 104
different post-RGB→YCbCr sample bytes and 13 different quantized coefficients
in the old floating surrogate. No different coefficient came from a block
whose input samples matched. With the Q16 integer surrogate, both traces and
JPEG bytes match under DMD/LDC. This localizes the observed divergence before
FDCT; it does **not** prove a specific compiler fault or universal byte
identity. `diagnose_compilers.py --float-color` and the default mode reproduce
both records. The Q16 and float JPEGs have a decoded maximum delta of eight,
mean 0.00159 and nearly equal PSNR versus raw on this case.

Five paired landscape rounds with three calls per sample gave LDC encode
medians of 188.084 ms Q16 versus 180.225 ms float. Candidate/float ratios
were 1.044, 1.434, 0.742, 0.992 and 1.130. The candidate spread was 36.3%,
float spread 33.9% and Pillow control spread 31.9%; there is no supported
speed claim. A separate `perf` sample attributed 39.2% of encode cycles to
the outer encoder and 29.0% to FDCT; decode samples were 33.7% chroma
post-processing, 19.6% IDCT and 15.6% Huffman symbol lookup. Those are
sampled shares, not speedup estimates.

The sparse-IDCT research variant is pixel-identical to the dense path on the
landscape when its floating accumulator is explicitly zeroed. Seven paired
rounds gave decode medians of 197.600 ms sparse versus 193.715 ms dense,
with 65.5% and 29.2% relative spreads. The supposedly unchanged encode
control moved in the same direction as several decode pairs, consistent with
host drift. The dense IDCT therefore remains the default; sparse IDCT is
kept only behind `JpegIdctSparse` for further controlled study. The first
sparse experiment omitted the explicit zero fill, causing gross real-image
pixel errors; the now-hard same-file oracle preflight catches this class of
failure before a timing report is accepted.

The 12-case real-content matrix (three sources × quality 30/90/100 at 4:2:0,
plus quality 90 at 4:4:4) now passes the strict maximum-three same-file
decoder tolerance, independent Pillow/ImageMagick reopen and DMD/LDC JPEG
byte equality with the Q16 surrogate. It also runs 64 deterministic byte
mutations and eight truncations per source/compiler with destination
canaries. Some mutations remain valid and are accepted. This does not
qualify malformed-input security or an editor workflow.

## Current decision after native-plane probe, 2026-10-29

The native-plane path has correctness evidence, **not** a representative
performance number. It removes hidden colour conversion from the proposed
format-core boundary, so future throughput comparisons must distinguish
native component decode from RGB conversion/upsampling and give both sides
the same ownership/allocation contract. The RGB convenience benchmark cannot
be relabelled native-plane throughput.

Three paired LDC rounds on `rgb-smooth-420`, CPU 0 affinity and three inner
calls, gave sparse-IDCT decode 78.828 ms median against dense 84.595 ms,
but pair ratios were 0.932, 0.901 and 1.190. The unchanged encode control
had candidate/legacy ratios 1.176, 1.162 and 0.868 (28.8% candidate
spread); `powersave` and frequency variation remain. The decoded pixels
matched exactly on this fixture. This is a *diagnostic*, not a controlled
speedup. Keep dense IDCT default and sparse behind `JpegIdctSparse`; do not
promote based on this three-round apparent median advantage. Full record:
`/tmp/imageio-jpeg-idct-current.json` (ephemeral, source/binary hashes inside).
The measured `jpeg_research.d` SHA-256 was
`0c17a3883792b8e5a1f6246d99955eff7f057571f460d888df9a84e98c688641`
(dirty Git tree, HEAD `e6fa00febf1f61bd9dc52c999de03178a0d1c6f9`);
sparse/dense binary SHA-256 values were respectively
`cee55b709497c516f36e937c853e0680a7640e347994afd58777abca890cbc7f` /
`a3c7b148fcde1b77c63164735b9c5e8db906a0b966713c6e7a2258b682547624`.
Subsequent source edits require a new measurement before treating those
numbers as current.

Keep the separable FDCT, packed entropy writer and direct Huffman lookup as
current research baselines. The earlier profile sampled FDCT and chroma
post-processing as substantial costs, but no new FDCT/Huffman candidate has
passed paired, equivalent-output and representative-content checks. Next
experiments should isolate entropy decode lookup, FDCT quantization and
native-plane output separately, then measure on a frequency-controlled host
with a retained source/binary record before changing defaults. There is no
performance admission decision for the codec.
