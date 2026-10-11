# Image I/O research questions

This is an evidence backlog, not an accepted design.

| Question | Evidence required | Initial reference |
|---|---|---|
| Does D Gamut cover our first concrete source formats? | Public API, format/sample limits, consumer build | https://codemirror.dlang.org/packages/gamut |
| Can an existing backend decode directly into raster-owned storage? | External ownership/stride experiment, lifetime negative probes | raster-d public API |
| Can TIFF/COG be read by window without decoding entire image? | Measured disk/HTTP bytes, blocks, copies, memory | https://gdal.org/ |
| Do 16-bit, float and multispectral channels preserve native values? | Independent sample oracle and metadata roundtrip | TIFF/GeoTIFF/OpenEXR |
| Which metadata belongs to codec vs image domain? | Schema crosswalk and loss audit | imagery-d ADR 0002 |
| Does the resource change during a read? | Snapshot/revision coherence tests | imagery-d ADR 0003 |
| Is an independent I/O package justified? | At least two realistic consumers or coherent reusable capability | workspace admission gate |

Investigate format parsing and decompression-bomb/malformed-input limits.
Separate codec-specific constraints from representation semantics. A file
extension is only a hint, not authoritative content identity.

Record every experiment with versions, exact input fixtures, hashes,
comparison basis, compiler/build mode, failures, peak RSS and data copies.
