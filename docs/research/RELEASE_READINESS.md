# imageio-d release readiness

Status: release candidate preparation. No preview or partial release is
authorized; the first complete 0.x release may proceed after the local
technical gates below pass.

The release requires qualified Read/Write contracts for TIFF, JPEG and PNG.
Research probes alone do not satisfy release support; the public DUB package,
independent oracle consumers, bounded error contracts and generated DDox are
the pre-release evidence. Real application integration is tracked as a
post-release validation gate.

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

- [x] TIFF Read/Write supported-variant matrix and independent consumer gate
- [x] JPEG Read/Write supported-variant matrix and independent consumer gate
- [x] PNG Read/Write supported-variant matrix and independent consumer gate
- [x] common source/sink, partial-I/O and failure contract
- [x] ownership/lifetime and metadata-loss contract
- [x] clean external consumer loads the package from its DUB release graph
- [x] package archive and licence contents are verified
- [x] DMD/LDC and rendered DDox baseline checks pass

## Pre-release audit result

- [x] freeze ImageRegion ownership and lifetime wording for the 0.x API
- [x] freeze structured error propagation for the 0.x API
- [x] broaden malformed and truncated input coverage through every public path
- [x] publish the range/overview cost report contract
- [x] run the complete CI matrix from clean checkouts
- [x] review public Ddoc and dependency versions for the final Read/Write API
- [x] make an explicit complete-format release-scope decision

## Post-release validation

- [ ] integrate a real editor or satellite application consumer
- [ ] repeat the performance matrix on an independent host/compiler
- [ ] expand the malformed-input corpus with sustained fuzzing
- [ ] review user-visible metadata and quality feedback from the first release

The implementation must not be presented as a complete implementation of every
TIFF, JPEG or PNG variant. The release scope and unsupported variants must be
quoted from the capability matrix. Post-release validation items are not
preconditions for the first 0.x package, but remain tracked commitments.
