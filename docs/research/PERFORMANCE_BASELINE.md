# Performance baseline — TIFF payload core

Date: 2026-10-25

This is research evidence, not a release benchmark. The benchmark uses
runtime-generated input, consumes the complete destination after every
iteration through a non-inlineable function, and reports copied bytes.

## Configuration

- host-local Linux x86-64;
- DMD `2.111.0`, `-O -release`;
- LDC `1.42.0`, `-O3 -release`;
- 20 iterations for the matrix cases;
- 1024 × 1024, 3 bands, 16-bit planar input;
- caller-owned interleaved destination;
- no compression or sample conversion.

## Result

| Path | DMD | LDC |
|---|---:|---:|
| specialized planar 3×16-bit | 403 ms | 187 ms |

The earlier 128 ms DMD result is rejected as invalid evidence: the benchmark
did not make every destination result observable and allowed compiler
elimination. The benchmark now uses a full non-inlineable checksum/consume
step.

## Interpretation

The specialized path is currently the preferred implementation for the common
3-band/16-bit planar-to-interleaved case. The generic blocked path was slower
than the simple loop and is retained only as a comparison experiment.

Future measurements must preserve the runtime-input and full-consume rules,
report compiler flags, copied bytes and checksums, and include repeated runs
before drawing performance conclusions.

## Compiler-specific tuning

The research harness now exposes a compiler-specific default tile candidate:

- DMD: 128×128, based on the current local matrix;
- LDC: 64×64, a stable middle candidate in the current matrix;
- unknown compilers: 64×64 fallback.

This is an internal tuning experiment only. It must not become a public API
contract or a version check until repeated measurements across supported
compiler versions and platforms justify it.

## Tile matrix snapshot

Run on the same local host, 1024×1024, one byte per sample, 20 iterations:

| Compiler | 16 | 32 | 64 | 128 | 256 |
|---|---:|---:|---:|---:|---:|
| DMD `-O -release` | 217 ms | 211 ms | 221 ms | 215 ms | 222 ms |
| LDC `-O3 -release` | 492 ms | 492 ms | 484 ms | 487 ms | 485 ms |

The matrix does not yet justify a permanent compiler-specific choice: DMD's
best observed value is 32×32, while LDC's is 64×64, and the spread is small
relative to normal host variance. The tuning module remains an experiment,
not a production constant.

Resource snapshot from `/usr/bin/time` on the same host:

| Binary | Elapsed | Max RSS |
|---|---:|---:|
| DMD optimized matrix | 0.88 s | 19,584 KB |
| LDC optimized matrix | 0.73 s | 19,836 KB |

The benchmark's payload copy totals and checksums remain the authoritative
correctness guard; RSS is environment-dependent.

Historical large-fixture snapshot, 1024×1024, 100 decode iterations per
process, three runs on the same host (2026-10-25):

| Path | DMD elapsed | LDC elapsed | DMD RSS | LDC RSS |
|---|---:|---:|---:|---:|
| Planar RGB | 0.68–0.69 s | 0.68–0.73 s | 12,812–12,844 KB | 9,928–10,268 KB |
| Tiled UInt16 | 0.45–0.47 s | 0.36–0.47 s | 9,736–9,864 KB | 7,988–8,096 KB |

**Withdrawn as correctness and performance evidence.** The optimized
`-release` build removed `assert` expressions, including the GDAL pixel
comparison and side-effecting external-array reads. The planar GDAL ENVI
export also inherited BSQ layout while the decoder produced BIP. The XOR
checksum happened to be zero for 100 repetitions. These figures cannot be
used as a decoder baseline.

## Corrected large-fixture gate (2026-10-30)

`tiff_planar_oracle.d` and `tiff_tile_oracle.d` now use checks that remain
active under `-release`, including parser/array/decode results and GDAL pixel
equality on the first and final iteration. Each iteration consumes every
output byte through a non-inlineable checksum; the rolling aggregate no
longer cancels equal outputs in pairs. The generator explicitly requests
ENVI BIP for the planar RGB reference. A same-length BSQ reference is rejected
by both optimized binaries as a negative control.

Host: local Linux x86-64; DMD 2.111.0 `-O -release`, LDC 1.42.0
`-O3 -release`; 1024×1024; 100 iterations/process; three process runs.

| Path | DMD elapsed | LDC elapsed | DMD max RSS | LDC max RSS |
|---|---:|---:|---:|---:|
| Planar RGB8, 384 strips | 1.05–1.16 s | 1.96–2.04 s | 12,820–12,956 KB | 12,844–13,104 KB |
| Tiled gray16, 16 tiles | 1.36–1.37 s | 3.53–3.78 s | 9,696–9,912 KB | 9,856–10,096 KB |

The planar input TIFF SHA-256 is
`61e305b2437cf0b3142bfe101b0b9a46cd2cc3e2a3090d25423d1eed67cc5f43`;
its BIP raw reference is
`57bc6c2e2caa5faed66730fa62b51bc15a18fd2da25aa1cc937c25b0d0e0cd9a`.
The tiled TIFF and raw reference hashes are
`95246b09c9525654700f7323a7b3930e637d2966e61cd67eb475857a06d8428a`
and `547fd0e66c1d61b49bd25cb1c17449a94eaa9d246e38e845951602373db00438`.
Single-iteration DMD aggregate checksums are `5990002958508482561`
(planar, 3,145,728 output bytes) and `16386529803297095681`
(tiled, 2,097,152 output bytes).

This is an end-to-end oracle-harness measurement, including full output
consumption and two pixel comparisons, not codec-only throughput. The planar
path preflights all 384 ranges, then copies each source sample directly from
its strip into caller-owned interleaved output. It reports 3,145,728 payload
bytes, zero staging bytes and 3,145,728 destination bytes written per
iteration. The tiled path likewise writes directly into caller-owned output.
The planar peak RSS fell from 20,472–20,672 KB (DMD) and 17,532–17,860 KB
(LDC) in the corrected staging harness to the ranges above. Allocation
evidence for the complete selected uncompressed corpus is now recorded below;
a second host remains open.

The small external-fixture matrix was also measured after `pixel_oracle.sh`.
Every path reports zero staging and one destination copy per sample byte.
Elapsed values are below the timer's 0.01-second resolution; peak RSS mostly
measures process/runtime overhead and is retained only as a bounded baseline.

| Fixture | Output/copy bytes | DMD max RSS | LDC max RSS |
|---|---:|---:|---:|
| gray8 single strip | 84 | 3,220 KB | 3,492 KB |
| RGB8 single strip | 351 | 3,196 KB | 3,580 KB |
| gray16 single strip | 256 | 3,196 KB | 3,800 KB |
| planar RGB8 | 351 | 3,068 KB | 3,732 KB |
| tiled gray16 | 418 | 3,176 KB | 3,524 KB |

The real-fixture protocol is `experiments/tiff_core/fixture_measure.sh` after
`pixel_oracle.sh`. It measures the actual external planar and tiled TIFF
oracles, including file read and metadata/array traversal. These numbers must
not be compared directly with the synthetic hot-loop matrix, but they expose
fixture-level latency and RSS.

For variance, use `experiments/tiff_core/fixture_variance_measure.sh [runs]`.
It reuses already compiled DMD/LDC oracle binaries and therefore measures the
fixture read/decode path rather than compilation overhead. Small fixtures may
fall below the timer resolution; larger generated fixtures are required before
making throughput claims.

Large-fixture generation is reproducible with
`experiments/tiff_core/large_fixture_generate.sh`. It creates 1024×1024
interleaved/planar RGB and 16-bit tiled grayscale inputs and their GDAL raw
exports. The current small-fixture oracles must be generalized for these
variable dimensions before their timings are admitted as decoder benchmarks.

That generalization is now available. Run
`experiments/tiff_core/large_fixture_measure.sh [runs] [iterations]` for
optimized DMD/LDC measurements of the 1024×1024 planar and tiled paths,
including peak RSS. The default is 3 process runs and 100 decode iterations
per process; larger iteration counts are supported but can take substantially
longer because the checksum consume is intentionally non-eliminable.

## Repeated-run protocol

`experiments/tiff_core/variance_measure.sh [runs]` executes the same optimized
matrix binary repeatedly and reports elapsed time plus peak RSS for each run.
The script is the required protocol for future tuning claims. A single run or
an isolated best value is not sufficient evidence for a compiler-specific
default.

Initial local three-run snapshot (same host, warm process-independent runs):

| Compiler | Run 1 | Run 2 | Run 3 | Max RSS range |
|---|---:|---:|---:|---:|
| DMD | 0.86 s | 0.85 s | 0.83 s | 19,512–19,652 KB |
| LDC | 0.96 s | 0.69 s | 0.69 s | 19,676–19,996 KB |

The first LDC run shows a cold-start effect in this measurement. These values
are evidence for variance handling, not a cross-platform performance claim.
