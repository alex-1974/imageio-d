# imageio-d release readiness

Status: release postponed. No preview or partial release is authorized.

The release requires qualified Read/Write contracts for TIFF, JPEG and PNG.
Research probes and bounded read-only experiments are evidence only; they do
not satisfy release support.

## Proposed first release scope

The first release candidate is intentionally limited to classic TIFF/COG
inputs with classic TIFF and BigTIFF UInt8/UInt16 samples, interleaved strips or
tiles, zlib Deflate, PackBits, LZW, grayscale JPEG-in-TIFF, Predictor 2, bounded ROI reads and technical
overview selection.
It does not
promise a complete TIFF implementation.

## Proven

- [x] transport-d v0.2.1 bounded range source
- [x] compression-d zlib Deflate integration
- [x] classic TIFF magic-number detection
- [x] classic TIFF IFD inspection
- [x] IFD-chain and overview inspection
- [x] explicit level selection
- [x] strip and tile range planning
- [x] UInt8 and UInt16 interleaved decode
- [x] UInt8 and UInt16 planar/interleaved imagery materialization
- [x] Deflate and Predictor 2 fixture consumers
- [x] PackBits and LZW codec integration against compression-d v0.2.0
- [x] independent GDAL PackBits fixture consumer qualification
- [x] independent GDAL LZW fixture consumer qualification
- [x] BigTIFF header/IFD and 64-bit strip/tile offset qualification
- [x] grayscale JPEG-in-TIFF with compression-d JPEG and JPEGTables
- [x] DMD/LDC external consumers
- [x] local-file and HTTP/COG consumer paths

Compression ownership: `imageio-d` selects and invokes codec functionality;
the compression algorithms and reusable decompression primitives remain in
`compression-d`.

## Deliberately unsupported

- [ ] TIFF PlanarConfiguration 2 decoding
- [ ] multi-component JPEG-in-TIFF native-plane materialization
- [ ] PNG and JPEG readers (separate format gates)
- [ ] implicit RGB(A) or radiometric conversion
- [ ] CRS/georeferencing interpretation

## Release gates

- [ ] TIFF Read/Write supported-variant matrix and independent consumer gate
- [ ] JPEG Read/Write supported-variant matrix and independent consumer gate
- [ ] PNG Read/Write supported-variant matrix and independent consumer gate
- [ ] common source/sink, partial-I/O and failure contract
- [ ] ownership/lifetime and metadata-loss contract
- [ ] clean external consumer loads the package from its DUB release graph
- [ ] package archive and licence contents are verified
- [x] DMD/LDC and rendered DDox baseline checks pass

## Known research gaps that remain release blockers

- [ ] freeze ImageRegion ownership and lifetime wording for a stable API
- [ ] freeze structured error propagation for a stable API
- [ ] broaden malformed and truncated input coverage through every public path
- [ ] publish the complete range/overview cost report contract
- [x] run the complete CI matrix from clean checkouts
- [ ] review public Ddoc and dependency versions for the final Read/Write API
- [ ] make an explicit complete-format release-scope decision

The current implementation must not be presented as a release or as complete
TIFF, JPEG or PNG support until all release gates above are resolved.
