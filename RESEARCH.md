# Image I/O research questions

This is an evidence backlog, not an accepted design.

## Product hypothesis

`imageio-d` is intended to be a Pure-D library from the beginning. Existing
image libraries are comparison references, not wrappers or runtime backends.
The project is attractive only if a D consumer gets a more natural API and a
better technical contract for native samples, metadata, regions, ownership and
`raster-d` integration. Both reading and saving are product requirements for
general and scientific image editing. `dunia` needs image I/O feeding
`imagery-d` satellite analysis. The exact per-format read/write subsets are
research questions, not currently supported capabilities.

| Question | Evidence required | Initial reference |
|---|---|---|
| Does D Gamut cover our first concrete source formats? | Public API, format/sample limits, consumer build | https://codemirror.dlang.org/packages/gamut |
| Can an existing backend decode directly into raster-owned storage? | External ownership/stride experiment, lifetime negative probes | raster-d public API |
| Can TIFF/COG be read by window without decoding entire image? | Measured disk/HTTP bytes, blocks, copies, memory | https://gdal.org/ |
| Do 16-bit, float and multispectral channels preserve native values? | Independent sample oracle and metadata roundtrip | TIFF/GeoTIFF/OpenEXR |
| Which metadata belongs to codec vs image domain? | Schema crosswalk and loss audit | imagery-d ADR 0002 |
| Does the resource change during a read? | Snapshot/revision coherence tests | imagery-d ADR 0003 |
| Is an independent I/O package justified? | At least two realistic consumers or coherent reusable capability | workspace admission gate |
| Which read/write formats and variants do the three target consumers actually need? | Consumer fixtures and a capability matrix with independent read and write cells | `docs/research/CONSUMER_READ_WRITE.md` |

## API-fit questions

| Question | Evidence required |
|---|---|
| What is the smallest natural D object model? | Competing snippets for source, reader, info, request, result and error |
| Which module and naming structure feels native to D? | Import/Doc comparison across five consumer flows |
| Are ownership and borrowing obvious? | DMD/LDC DIP1000 compile probes and lifetime negative tests |
| Does the API compose with `raster-d` without duplicate concepts? | Storage/view/ROI/stride/lease integration experiment |
| Does it avoid accidental image semantics? | Tests proving no implicit RGBA, scaling, colour or NoData mapping |
| Can a consumer export without hidden conversion or metadata loss? | Explicit encoder representation/options and round-trip/loss-policy tests |

## Pure-D implementation questions

| Question | Evidence required |
|---|---|
| Which first format is feasible and useful? | Consumer need, specification/licence review, implementation estimate |
| Can native samples and technical metadata be preserved? | Differential corpus and independent decoder oracle |
| Can useful region/tile access be implemented? | Tile/strip/window measurements and exact ROI comparisons |
| Is performance competitive enough? | DMD/LDC benchmarks against direct reference implementations |
| Is malformed-input handling bounded and safe? | Fuzz/property corpus, dimension/memory limits and negative tests |

Investigate format parsing and decompression-bomb/malformed-input limits.
Separate codec-specific constraints from representation semantics. A file
extension is only a hint, not authoritative content identity.

Current format hypothesis: TIFF core is the first meaningful Pure-D slice for
`imagery-d`, because it exercises multi-band native samples, strips, tiles and
technical metadata. GeoTIFF/COG are follow-up gates, not implied support.
JPEG and PNG read/write are separate editor-driven gates; this first TIFF
experiment does not establish their implementation order or public API.

Performance direction: parser, bounds checks, tile traversal, caller-owned
decode and allocation-free conversions should be `@nogc` where practical.
Research must compare structured Result/status errors with exception-based
convenience APIs and record every allocation boundary.

Record every experiment with versions, exact input fixtures, hashes,
comparison basis, compiler/build mode, failures, peak RSS and data copies.

## Admission rule

Do not create production modules, a public DUB package or a universal codec
API until the API-fit, Pure-D format and consumer evidence together identify a
small independently useful capability.
