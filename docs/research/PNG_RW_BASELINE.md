# PNG read/write research baseline

Date: 2026-10-27. This is a local, single-host research snapshot, not a
release/performance acceptance result.

## Reproduction

From `experiments/png_rw/` run `sh check.sh` for the correctness matrix and
`sh bench.sh` for this measurement. The benchmark generates a deterministic
128×128 RGB8 PNG with Pillow, then runs five warmed decode iterations and five
warmed encode iterations on the same source under each compiler. Bounds checks
remain on. A checksum is consumed every iteration. The reference PNG is
17,394 bytes (SHA-256
`eebbe756e146b359860a003d79e8cc49c82584c905beb6c8e16ba0efa5eed6e4`);
the native raw samples are 49,152 bytes (SHA-256
`d60bdb8f80b1109cd9ef88748e5192c40d40e2a0b20a321c7a030ec538ef6031`).

Environment: Linux 6.17.0-22-generic x86-64, Intel Core i7-9750H; DMD
2.111.0, LDC 1.42.0; Pillow 12.3.0, ImageMagick 7.1.2-31. Local
`compression-d` checkout commit `971fa46`, with
`source/compression/encode.d` SHA-256
`abc5da0e522c9b1d1fe2ba8043e2a1c76e2f9e0899d31b7ac48b2257873d0af7`.
Flags: DMD `-O -release -boundscheck=on`; LDC `-O3 -release
-boundscheck=on`. The benchmark does not include compilation or fixture
generation in measured milliseconds.

| Compiler / session | Decode, 5 iterations (ms) | Encode, 5 iterations (ms) | Output bytes | Peak RSS (KiB) |
|---|---:|---:|---:|---:|
| DMD A, rounds 1/2/3 | 9 / 9 / 9 | 1925 / 1943 / 1940 | 34,211 | 3576 / 3584 / 3600 |
| LDC A, rounds 1/2/3 | 3 / 4 / 3 | 1195 / 1199 / 1162 | 34,211 | 3756 / 3764 / 3728 |
| DMD B, rounds 1/2/3 | 10 / 9 / 9 | 1065 / 1043 / 1006 | 34,211 | 3600 / 3676 / 3596 |
| LDC B, rounds 1/2/3 | 4 / 3 / 4 | 1171 / 1213 / 1236 | 34,211 | 3740 / 3824 / 3860 |

The D encoder's output is independently decoded byte-exactly, but its
34,211-byte file is about 1.97× the reference file. This is **not** an
equivalent-encoder speed comparison: Pillow and the D path use different
filter/compression choices. The D benchmark includes CRC32 result consumption
in each timed loop. The same-host DMD encode time changed substantially
between sessions A and B; these runs do not establish a stable DMD/LDC ranking
or a regression tolerance. Even so, the current native encoder is much slower
than its own decoder on this small input; it cannot support a competitive
editor performance claim. The current `encodeZlibStored` path uses a bounded but
naive fixed-Huffman/LZ search and filter-0 scanlines. Faster compression,
filter selection, streaming row output and memory/copy reduction remain
separate work. Repeat on a second host and representative large images before
any throughput gate.

## Historical toolchain caveat (before compression-d issue #8)

At the provider snapshot used for the first PNG baseline, the local PNG
modules and compile-only API probe compiled under DMD/LDC `-dip1000`, while
the imported `compression-d` encoder failed at `BitWriter.put`/`finish`
scope-this calls. The normal DUB DMD/LDC build passed. This was an open
fully linked consumer gate at that snapshot; it is now closed by the
remote-master validation recorded below.
The provider follow-up is recorded in
[`compression-d` issue #1](https://github.com/alex-1974/compression-d/issues/1#issuecomment-6451155535),
with the [second-session correction](https://github.com/alex-1974/compression-d/issues/1#issuecomment-6451179014).
A focused reproducer and acceptance gate are in
[`compression-d` issue #8](https://github.com/alex-1974/compression-d/issues/8).

## 2026-10-27 row-bounded speed/size probe

The experiment now has two *explicit* encoder choices. The original
fixed-Huffman/LZ path remains the smaller-file baseline. A second Pure-D
stored-block path compresses one filter-0 row at a time; it can either write
into a caller-owned complete PNG buffer or produce one complete IDAT chunk per
call for an external sink. It is a speed/residency choice, not equivalent
compression. The chunk writer state remains caller-owned and is 32,888 bytes
on this x86-64 build, largely its `compression-d` history.

The same 128×128 RGB8 fixture and benchmark script, optimized bounds-checked
DMD 2.111.0 / LDC 1.42.0, five iterations per round, gave:

| Compiler | Fixed-LZ encode, 3 rounds (ms/5) | Stored rows, 3 rounds (ms/5) | Filter-copy phase (ms/5) | Deflate-only phase (ms/5) |
|---|---:|---:|---:|---:|
| DMD | 1950 / 2002 / 2023 | 2.89 / 2.99 / 3.06 | 0.76 / 0.84 / 0.79 | 1953 / 2008 / 2021 |
| LDC | 1242 / 1403 / 1223 | 1.69 / 1.70 / 1.83 | 0.50 / 0.50 / 0.56 | 1437 / 1218 / 1216 |

The fixed-LZ output is 34,211 bytes; stored rows output is 49,983 bytes;
Pillow's differently filtered/compressed reference is 17,394 bytes. The
phase split establishes that the current fixed-LZ search dominates this
fixture, not row copying or PNG chunk assembly. The measurements do **not**
establish a fair speed comparison against Pillow or a stable cross-host
compiler ranking. Stored rows are much faster but 2.87× the reference file
size. Better Pure-D LZ match finding, filter selection and a balanced
speed/size mode remain open `compression-d`/PNG research; no provider source
was changed here.
The pull-style writer emits one IDAT per row, so its serialized file is
larger than the single-IDAT stored variant by 12 bytes per additional row;
that overhead was not included in the first timed stored-buffer run. A later
run timed both stored variants: the pull-style output was 51,507 bytes, with
2.73–2.89 ms/5 calls under DMD and 1.69–1.71 ms/5 under LDC, close to the
single-IDAT stored-buffer path's 2.68–2.81 ms and 1.65–1.75 ms respectively.
The timing consumes CRC32 of each emitted chunk; it is not filesystem I/O.

A later repeat with row-decoder timing added varied further: full decode and
row decode were both about 4–6 ms/5 under LDC and 13–21 ms/5 under DMD;
stored encode was about 2.8–3.5 ms/5 under LDC and 3.3–4.6 ms/5 under DMD.
Fixed-LZ encode varied from roughly 1.3 to 2.1 s/5 across those runs. These
figures are not a compiler acceptance threshold; host contention and
session-to-session variation need control before a performance gate.

For this fixture, full-image decoder compressed+filtered scratch is 66,617
bytes, versus 769 bytes of row scratch in the IDAT-slice decoder. Full-image
encoder filtered+zlib scratch is 104,736 bytes, versus 385 bytes of row
scratch in the stored path. These figures exclude caller-owned source/output,
`InflateWorkspace`, writer state and runtime overhead; they are **not** peak
RSS. The old and new paths execute in one benchmark process, so its roughly
3.7–4.2 MiB peak RSS cannot isolate a per-path residency claim. The reader
still receives the whole PNG file; a bounded file/range source and a
partially written sink contract remain separate work.

## 2026-10-28 adaptive-filter probe

`encodePng` now offers an explicit adaptive row-filter heuristic (minimum
sum of absolute signed residuals over PNG filters 0–4) before the same
Pure-D fixed-LZ encoder. The independent output oracle passes under DMD/LDC.
On the deterministic 128×128 RGB8 fixture, adaptive output is 17,035 bytes,
versus 34,211 bytes for filter-0 fixed-LZ, 49,983 bytes for stored rows and
17,394 bytes for the Pillow reference. This does not imply equivalent quality
settings or compression algorithms. With five warmed encodes per round and
the same CRC-consumed benchmark, adaptive took 1140/1020/1014 ms under DMD
and 1189/1135/1351 ms under LDC. The filter heuristic itself is small
relative to the current fixed-LZ cost. Thus the size target improved on this
fixture, but the balanced *speed/size* gate remains open. A faster Pure-D
match finder or another bounded compressor strategy needs independent work.

## 2026-10-28 bounded hash-chain Deflate probe

To test that speed/size compromise without changing another repository, the
PNG research experiment now includes a temporary fixed-Huffman Deflate
encoder with a 32K hash-chain window and at most 32 candidate matches per
position. This is **not** intended as permanent imageio-owned compression;
the general strategy belongs in `compression-d` after its own review and
tests. It uses caller-owned 262,144 bytes of hash tables plus the existing
filtered/zlib staging. DMD/LDC independent PNG decode oracles pass, including
random RGB and one-pixel images.

On the 128×128 RGB8 fixture it emits 17,088 bytes, just 53 bytes larger than
the slow adaptive/provider path and 306 bytes smaller than the Pillow
reference (different settings). Five warmed encodes took 23.5/22.4/23.6 ms
under DMD and 10.4/10.9/11.6 ms under LDC; same-run adaptive/provider times
were 2180/2103/2011 ms and 675/705/766 ms respectively. CRC consumption is
inside each timed loop; the timings are not filesystem I/O or cross-host
acceptance thresholds. This is a promising *single-fixture* middle strategy,
not yet a qualified balanced default. Broader image types/sizes, match-search
edge cases, fuzzing, memory/copy profile and provider integration were open
at the time of this local probe; the latter is addressed below.

## 2026-10-28 provider hash-chain integration

The active PNG experiment now uses `compression.encode.HashChainMatchFinder`
and `encodeRawFixedLzHashChain`; the local Deflate implementation was moved to
`experiments/png_rw/archive/` as historical research evidence and is no longer
compiled. PNG adds only zlib header and Adler-32 trailer around the provider's
raw stream. The finder is caller-owned and reset for each independent image.
This does not yet provide a general streaming zlib encoder in `compression-d`.

`sh check.sh` passes DMD/LDC compilation and independent PNG decode oracles,
including the faster encode path. The 128×128 RGB8 output remains 17,088 bytes.
The provider finder is 294,936 bytes on this x86-64 host versus the archived
prototype's 262,144-byte hash tables; both are additional to filtered/zlib
staging. It retains a 32-KiB history to support cross-chunk operation.

Same-host `sh bench.sh` snapshot: Linux 6.17.0-22, DMD 2.111.0, LDC 1.42.0,
provider checkout `82b8c52`, `source/compression/encode.d` SHA-256
`7fa0796955c2108ce9bae63476ee82972dcbdbcd13f2c900738746ff2d6252d8`.
This first provider run predates the stack-owned `ref` API split. Five warmed
encodes per trial, three rounds, optimized release with bounds
checks, CRC32 consumed within the loop, no compilation or file I/O timed:

| Compiler | Provider hash-chain, ms/5 | Adaptive fixed-LZ, ms/5 | PNG bytes |
| --- | ---: | ---: | ---: |
| DMD | 37.18 / 34.44 / 36.97 | 1709.57 / 1642.11 / 1722.32 | 17,088 |
| LDC | 13.85 / 15.15 / 15.43 | 988.54 / 1001.31 / 987.51 | 17,088 |

These measurements are a new session and not an apples-to-apples comparison
with the archived prototype's earlier timings. Broader corpus, host, and
fully linked DIP1000 provider qualification were open at this snapshot. No
public API or production format admission follows from this integration.

The next API-fit pass split the fixed and fast paths into `encodePng` and
`encodePngHashChain` (and corresponding metadata-transfer functions). The fast
path takes `ref HashChainMatchFinder`, so a caller can own the 294,936-byte
state on the stack without GC allocation or unsafe pointer conversion. Both
paths share the same preflight/filter/chunk body via a private compile-time
codec choice; the fixed path has no large dummy state. The independent PNG
oracle and compile-only `@safe pure nothrow @nogc`/DIP1000 probe pass under
DMD and LDC. This is a research API improvement, not a public API decision.
At that point, fully linked provider DIP1000 still failed as described above;
the later remote-master gate is recorded below.

After the `ref` API split, the same benchmark script and fixture gave
39.54–42.06 ms/5 fast encodes under DMD and 15.24–16.88 ms/5 under LDC;
the output remained 17,088 bytes. The fixed-LZ adaptive path ranged
1.74–1.81 s/5 (DMD) and 1.06–1.08 s/5 (LDC) in that session. The
same-session comparison still shows the fast path's large advantage, but
the difference between the two provider sessions is not an isolated API
overhead measurement: host load/frequency were uncontrolled. Peak process
RSS was 4,136–4,220 KiB (DMD) and 4,368–4,384 KiB (LDC), not a
per-path memory estimate.

## 2026-10-28 remote-master DIP1000 and PNG consumer gate

A fresh, separate checkout of `compression-d` remote `master` at
`b0fc8d74e96219536db9709e49e7078c5856f92a` was tested without
switching the active provider checkout. Its `source/compression/encode.d`
SHA-256 is
`ec97df019e6eed228af81f58d9c19c63d5bc7c6b3b6216afabf451b9b7a898d6`.
The provider's `scripts/check-encode-dip1000.sh` passed; DMD and LDC each
passed 11/11 compression-d unittest modules. From `experiments/png_rw/`,
`COMPRESSION_D_ROOT=<fresh-master-checkout> sh check.sh` compiled and
**fully linked** the imageio PNG consumer with that exact provider under
`-dip1000` for both compilers. The resulting binaries passed the complete
independent Pillow/ImageMagick/Python PNG input/output oracle. The normal
local DUB-path `sh check.sh` also passed separately. Thus issue #8's
consumer-side DIP1000 blocker is closed for this pinned toolchain and corpus;
it does not certify all future provider revisions or PNG variants.

The corresponding `COMPRESSION_D_ROOT=<fresh-master-checkout> sh bench.sh`
snapshot used the same deterministic 128×128 RGB8 fixture, optimized release
with bounds checks and DIP1000, five warmed iterations per round, three
rounds, CRC consumption inside the timed loop. DMD 2.111.0: provider
hash-chain 37.32 / 38.67 / 37.05 ms per five encodes; adaptive fixed-LZ
1673.96 / 1616.79 / 1659.19 ms. LDC 1.42.0: hash-chain
14.74 / 14.31 / 15.20 ms; adaptive fixed-LZ
1066.86 / 1012.95 / 1027.81 ms. The hash-chain PNG remained 17,088 bytes.
Peak process RSS was 4,252–4,264 KiB (DMD) and 4,344–4,412 KiB (LDC).
This is a single-host, single-fixture snapshot, not a release threshold or
an isolated comparison of provider commits.

### zlib ownership decision (research, not provider API admission)

The active imageio experiment calls `encodeRawFixedLzHashChain` and adds a
two-byte zlib header plus Adler-32 trailer. No local LZ77 search or Deflate
bit writer remains in the active build; the old implementation is archived.
Framing a generic Deflate stream is conceptually compression-d's domain, but
the current wrapper is small, explicit, allocation-free and independently
decoded by the PNG oracle. A new provider one-shot hash-chain zlib function
would be useful only after its result/capacity, workspace reset, overflow and
streaming semantics are agreed and a second consumer or stable API need is
shown. **Decision: defer a new compression-d API request for now.** This does
not claim that PNG owns generic zlib framing permanently. Revisit before a
production imageio dependency/API is admitted; do not copy the Deflate
algorithm back into imageio.
