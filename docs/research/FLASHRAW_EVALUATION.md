# FlashRaw algorithm evaluation

Issue #2 is a research comparison, not an invitation to add FlashRaw, Rust,
FFI or a camera-RAW dependency. The source was inspected at the current
upstream `main` revision on 2026-11-07:

- architecture: https://github.com/ybouane/flashraw/blob/main/docs/architecture.md
- packed samples: https://github.com/ybouane/flashraw/blob/main/crates/flashraw-codecs/src/packed.rs
- speculative entropy: https://github.com/ybouane/flashraw/blob/main/crates/flashraw-codecs/src/par_entropy.rs

## Findings

| FlashRaw technique | imageio-d applicability | Decision |
|---|---|---|
| Cheap metadata/header parse | TIFF/GeoTIFF already separates bounded inspection from payload reads. | adopt: preserve the separation and bounds checks. |
| Packed scalar/SIMD unpacking | Relevant only after a real packed TIFF/DNG consumer exists. Current admitted samples are 8/16-bit. | defer: first add a concrete packed-sample fixture and oracle. |
| Independent tile/strip decode | Directly relevant to the current TIFF/COG path. | adopt: intersecting block traversal is already used and measured. |
| Direct destination writes | Relevant to ROI and bounded residency; owned by the caller/raster handoff, not a private imageio scheduler. | adopt: keep caller-owned output and explicit strides. |
| Speculative single-stream entropy | Requires codec-specific self-synchronisation and a bit-exact fallback. Current TIFF/JPEG paths do not justify it. | reject for current scope; revisit only with a real workload. |
| Generic parallel scheduler/GPU pipeline | Outside imageio's encoded-format boundary. | reject. |
| mmap as mandatory input | Unsafe as a universal source contract and unnecessary for current range probes. | reject as default; optional future source experiment only. |

## D-native baseline decision

The current Pure-D baseline already measures the two techniques that have a
real consumer-shaped justification: intersecting block traversal and direct
caller-owned output. No FlashRaw source, runtime, build dependency or API is
introduced. Packed SIMD and speculative entropy are not admitted without a
format-specific corpus, independent oracle, malformed-input tests and a
measured consumer benefit.

This closes the research decision for the present scope as `adopt` for the
bounded traversal/ownership principles, `defer` for packed optimisation and
`reject` for generic speculative scheduling/GPU/mmap requirements. It does
not claim camera-RAW format coverage or production performance parity.
