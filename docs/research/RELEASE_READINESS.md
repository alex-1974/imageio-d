# imageio-d release readiness

Status: unreleased research-backed develop API.

## Proposed first release scope

The first release candidate is intentionally limited to classic TIFF/COG
inputs with classic TIFF and BigTIFF UInt8/UInt16 samples, interleaved strips or
tiles, zlib Deflate, PackBits, LZW, grayscale JPEG-in-TIFF, Predictor 2, bounded ROI reads and technical
overview selection.
It does not
promise a complete TIFF implementation.

## Proven

- [x] transport-d v0.1.1 bounded range source
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

## Admission blockers

- [ ] freeze ImageRegion ownership and lifetime wording
- [ ] freeze structured error propagation
- [ ] qualify malformed and truncated inputs through the public API
- [ ] publish the complete range/overview cost report contract
- [ ] run the complete CI matrix from clean checkouts
- [ ] review public Ddoc and dependency versions
- [ ] make an explicit first-release scope decision

The current implementation must not be presented as a complete TIFF or image
library until the admission blockers are resolved.
