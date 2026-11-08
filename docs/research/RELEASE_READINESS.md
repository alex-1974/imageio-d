# imageio-d release readiness

Status: release-preparation for a deliberately limited `0.1.0-preview`.

The preview may ship with the open items below when they are stated as
limitations in the README, Ddoc and changelog. They remain blockers for a
stable support promise, not for this bounded preview.

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

## Preview release gates

- [x] explicit read-only TIFF/GeoTIFF/COG scope and unsupported list
- [x] README, changelog and module-level Ddoc describe the preview boundary
- [x] DMD/LDC and rendered DDox checks pass from a clean dependency graph
- [ ] clean external consumer loads the package from its DUB release graph
- [ ] package archive and licence contents are verified

## Deferred limitations

- [ ] freeze ImageRegion ownership and lifetime wording for a stable API
- [ ] freeze structured error propagation for a stable API
- [ ] broaden malformed and truncated input coverage through every public path
- [ ] publish the complete range/overview cost report contract
- [x] run the complete CI matrix from clean checkouts
- [x] review public Ddoc and dependency versions for the preview
- [x] make an explicit bounded preview-scope decision

The preview must not be presented as a complete TIFF or image library. The
deferred items remain release notes and follow-up gates, not implied support.
