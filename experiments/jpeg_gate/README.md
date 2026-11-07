# JPEG read/write research probe

This remains an internal Pure-D experiment, **not** a supported codec, public
API or DUB package. The codec functions compile as `@safe pure nothrow @nogc`.

`sh check.sh` runs DMD/LDC with DIP1000 and bounds checks against independent
Pillow and ImageMagick oracles. The 19×11 corpus covers baseline 8-bit gray and
YCbCr 4:4:4/4:2:2/4:2:0, five encoder qualities (1/30/75/95/100), all three
writer sampling choices, restart interval 1, EXIF/ICC copy-or-discard, an ICC
profile split across two APP2 segments, unsupported variants and malformed
markers. Output bytes are compared across DMD/LDC. Every baseline source byte
is also flipped once and every prefix is decoded (2,088 mutation/truncation
probes per compiler) with destination canaries. This is bounded robustness
evidence, not a security audit or fuzzing campaign. It also invokes the
local native-plane/I/O probe at the end.
It also runs a native-plane EXIF/ICC read-policy probe and a technical
read–modify–write surrogate with single- and two-segment ICC, checking
Pillow/ImageMagick reopen and explicit metadata copy versus discard. These
are not actual consumer integration tests.
The same runner also tests `jpeg_stream_header.d`: a fixed-state, pull-based
scan through SOS against short-read and paused sources, including a 70 kB
two-segment ICC payload. The caller must hand its pending prefetched bytes
to any following entropy reader. This is header inspection only; the tested
source simulates short reads in memory. On Linux, `jpeg_stream_pipe_probe.d`
also drives that scanner through a real nonblocking OS pipe and checks exact
pending-byte/pipe-suffix reconstruction. Its fixture producer is prebuffered;
the pixel codec still requires a complete encoded byte slice.

`sh stress.sh` uses optimized **release builds with bounds checks** for
1×1, 17×19, 257×193 and 256×256 generated images. It exercises restart-marker
rotation over many MCUs and checks Pillow/ImageMagick decoding, dimensions,
sampling, byte counts and lossy error. These are synthetic patterns, not a
representative editor/photo corpus.

`sh native.sh` checks the no-conversion component-plane experiment and a
resumable, fixed-window transfer contract under DMD/LDC. It also independently
reopens the encoded JPEGs with Pillow and ImageMagick. This is still a prebuffered codec; the
transfer does not prove streaming decode/encode. `sh external_malformed.sh`
fetches ten independently sourced, SHA-256-pinned invalid JPEGs from the
MIT-licensed jpeg-decoder crash-test group via a pinned codec-corpus revision and tests
graceful rejection plus destination canaries under both compilers. Network is
needed for that separate gate. Provenance and per-file MIT terms are in the
[pinned corpus SOURCES](https://github.com/imazen/codec-corpus/blob/ac980c295cb62c925d03d47990925d49c36eef18/jpeg-conformance/SOURCES.md).
Ten seeds are a smoke corpus, not fuzzing or security qualification.

`sh bench.sh --rounds 5 --cpu 0 --output /tmp/imageio-jpeg-benchmark.json`
runs the paired DMD/LDC/Pillow benchmark. Omit `--cpu` where CPU 0 is not
available; `--case gray-gradient` selects a smoke case. The suite covers
grayscale, smooth RGB 4:4:4, textured RGB 4:4:4 and smooth RGB 4:2:0. It
checks independent decoders and retains exact-input decode comparisons,
per-round timings, host/toolchain/fixture hashes and variability indicators.
Optional hash-pinned photographic cases, inner repetitions, separate `perf`
profiles and paired legacy/packed bitwriter comparisons are available via
`--case real-landscape-420`, `--inner-repeats`, `--profile` and
`--compare-bitwriter`. `--compare-color-transform` and `--compare-idct`
retain the old numerical/kernel variants for paired mechanism tests.
`diagnose_compilers.py` locates DMD/LDC sample/coefficient differences;
`corpus_gate.py --corpus-dir /tmp --output /tmp/imageio-jpeg-corpus.json`
checks the hash-pinned real-content quality matrix and bounded malformed
canaries. The corpus script requires the pinned source filenames in the
chosen directory or downloads them when `--corpus-dir` is omitted. CPU
affinity is not a frequency lock.
It is a **directional research benchmark**, not a performance qualification:
Pillow allocates while the D calls use preallocated caller-owned buffers, and
the two encoders do not generate equivalent JPEG bytes or file sizes. See
`docs/research/JPEG_BENCHMARK_METHOD.md` for the protocol and interpretation.

The writer uses caller-owned memory and explicit quality, sampling, restart
and metadata policy. Supplied EXIF (APP1) and ICC (APP2) bytes default to
rejection; opt-in copy or discard is available. A separate header scanner
reports borrowed EXIF and ordered ICC segment offsets. Neither path applies
EXIF orientation or ICC transforms. Pixel decoding still does not implicitly
inspect or preserve metadata; the caller must select that path explicitly.
The `decodeJpegPlanesAudited` experiment enforces an explicit EXIF/ICC and
other APP/COM report/discard choice before native-plane decode. Non-default
JFIF and Adobe container fields are counted as loss risks. It does not
preserve arbitrary metadata or define an
admitted consumer API.
Decoding can leave partial destination rows on a later entropy error; a failed
result makes destination contents unspecified.
The current RGB↔YCbCr transforms exist only in this internal oracle surrogate;
they are not the intended public image-I/O colour API. Native components and
an explicit `color-d`/application adapter are discussed in
`docs/research/JPEG_COLOR_BOUNDARY.md`; source/sink and partial-write questions
are in `docs/research/JPEG_SOURCE_SINK_CONTRACT.md`.

Cross-MCU chroma interpolation now uses two fixed Chroma row buffers after
entropy validation. The 17×19 and 257×193 subsampled stress cases differ
from Pillow by at most three levels across MCU boundaries. A separate 1×19
case differs by up to 27: libjpeg-turbo uses nearest-neighbour upsampling for
such narrow components while this probe retains 3:1 interpolation. This is
bounded evidence, not a general image-quality guarantee.

Open: optimized entropy coding and competitive throughput,
representative real-world/malformed corpora beyond the ten external seeds,
complete read-side metadata/loss policy, end-to-end consumer workflows,
and a source/sink API with documented partial-write semantics. Progressive,
CMYK/YCCK, arithmetic, 12-bit, MPO and JPEG XL are separate variant decisions.
