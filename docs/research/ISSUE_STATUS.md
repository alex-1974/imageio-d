# Open issue implementation status

This document is the local, evidence-backed status of GitHub issues 1–15.
It does not close GitHub issues or admit a public package. A checked item has
an executable probe or a documented implementation in this repository.

Issue #18 is implemented in the current research branch: the public region
contract exposes distinct geometry states and an exact `sampleCenter` helper;
JPEG 4:2:0 and 4:2:2 public-region tests cover all four odd/even ROI-origin
combinations, one-pixel and boundary-ending windows, invalid regions, plane
origins, crop phases and metadata propagation. The
decoder still intentionally reports unavailable JPEG phase when the source
does not prove a siting convention.

## GeoTIFF/COG track

| Issue | Status | Evidence / remaining boundary |
|---|---|---|
| #1 standalone scope | release-candidate | Reference matrix, public read/process/write consumer, API probes and admission decision exist. Local technical gates run in CI; real application integration and second-host evidence are tracked post-release. |
| #3 GeoTIFF/COG consumer requirement | probe-complete | Sentinel-2 metadata/window oracle, bounded local/HTTP ranges, overviews and UInt16 window comparison pass. No stable public API is admitted. |
| #4 GeoKey oracle | implemented for technical inspection | GeoKey directory is bounds-checked, preserved and supports inline SHORT lookup plus model/raster/geographic-CRS/projected-CRS IDs. GDAL fixture comparison passes. CRS object construction remains outside imageio. |
| #5 inspection result | implemented in research API | Dimensions, samples, layout, compression, tiling, predictor, raw NoData value, GeoKey values and affine tag values are exposed. |
| #6 tiled UInt16 Deflate | implemented/probed | Predictor-2 tiled window decoding passes DMD/LDC, native sample oracle and truncated-input checks. |
| #7 range source | implemented/probed | Bounded local and HTTP range probes report requests, bytes, amplification and failures. Cache/scheduler/cancellation remain excluded. |
| #8 overview reporting | implemented/probed | Explicit level inspection/selection and decode results now report `levelIndex` and `usedOverview`; no hidden resampling is performed. |
| #9 raster handoff | probe-complete | Caller-owned bytes, stride, lifetime and retained raster-d lease handoff pass in the consumer probe. |
| #10 Sentinel-2 comparison | reproducible probe | GDAL metadata and native UInt16 window hashes are recorded. Offline pinned fixture and real imageio consumer admission remain open. |

## Cross-cutting performance research

| Issue | Status | Evidence / remaining boundary |
|---|---|---|
| #2 FlashRaw evaluation | research decision complete | `FLASHRAW_EVALUATION.md` records source review and adopt/defer/reject decisions. No FlashRaw/Rust/FFI dependency is introduced; packed SIMD remains deferred until a real packed-sample workload exists. |

## JPEG plane track

| Issue | Status | Evidence / remaining boundary |
|---|---|---|
| #11 plane-grid contract | implemented in research API | Exact rational offsets, independent sampling factors and neutral component roles exist. No upsampling or colour conversion is performed. |
| #12 decoder propagation/ROI | partially implemented | Native plane metadata and ROI offsets propagate through the current baseline path. Full decoder-level coverage for every MCU/block/overview path remains open. |
| #13 geometry states | implemented | `unavailable`, `known`, `unsupported`, `conflicting` and `invalid` are distinct; `valid` requires `known`. Positive/negative unit tests exist. |
| #14 odd-origin ROI semantics | implemented for current path | Plane origin and rational reference offsets preserve odd crop phase; DMD/LDC tests pass. Broader source-siting corpus remains open. |
| #15 clean delivery | review-scope check implemented | `check_review_scope.sh` verifies that compiler products are ignored and no unignored build artefacts enter review. A focused commit/PR is still required. |

Issue #16 delivery material is covered by
`IMAGE_REGION_CONTRACT.md`, `IMAGE_REGION_UNSUPPORTED.md` and the public
`imageio.tiff` unittests that inspect the returned `ImageRegion` for JPEG
4:2:0/4:2:2, odd dimensions, odd-origin ROIs, padded strides, geometry
states, source-colour metadata and malformed geometry descriptors.

## Explicit non-completion conditions

The following are explicitly post-release validation items or outside the
declared 0.x scope:

- a real external editor or satellite consumer read/process/write path;
- independent second-host/compiler performance evidence;
- complete production-grade PNG/JPEG/TIFF API admission;
- full JPEG metadata preservation and all colour/siting variants;
- release packaging and public API freeze.

These are follow-up validation items, not blockers for the declared 0.x
technical scope. The repository remains research-coordinated until the release
checklist is signed off; no unsupported variants are implied by the candidate.

## Verification

The following currently pass:

```text
./check.sh                         # DMD + LDC
experiments/geotiff_metadata/check_inspection.sh
experiments/geotiff_metadata/check_range_decode.sh
experiments/geotiff_metadata/check_cog_gate.sh
experiments/jpeg_gate/check.sh
```

The complete local sequence is available as:

```text
./check_all_research_gates.sh
```

It currently passes package, review-scope, GeoTIFF/COG, JPEG, PNG,
`raster-d` handoff and public TIFF consumer gates.

