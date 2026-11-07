# JPEG codec boundary contract

Status: implemented research contract; not yet a released API.

## Ownership

`compression-d` owns the reusable JPEG codestream codec:

- marker parsing and baseline frame validation;
- quantization and Huffman table validation;
- entropy decoding/encoding, DCT/IDCT and restart handling;
- sampling geometry and native component planes;
- caller-owned storage, limits and structured codec errors.

`imageio-d` owns the file/container adapter:

- JPEG SOI/file-range orchestration;
- TIFF compression values 6 and 7 (old-style and new-style JPEG);
- strip/tile range acquisition through `transport-d`;
- JPEG marker metadata discovery and loss reporting;
- conversion between the codec's native planes and `ImageRegion` only when
  explicitly requested by the caller.

`imagery-d`/`color-d` own image meaning:

- RGB/YCbCr interpretation and conversion;
- ICC, gamma and rendering intent;
- orientation and display policy;
- raster materialization and semantic channel naming.

## Codec input and output

The first admitted codec subset is baseline sequential 8-bit grayscale and
three-component YCbCr/JPEG with 4:4:4, 4:2:2 and 4:2:0 sampling. Progressive,
arithmetic, CMYK/YCCK, 12-bit and lossless JPEG require separate gates.

The decoder accepts a borrowed encoded byte range and writes to caller-owned
native component planes. Each plane declares its byte span, width, height and
row stride. The codec does not allocate, retain the source, or silently convert
YCbCr to RGB.

The encoder accepts caller-owned native planes and a caller-owned output buffer
or explicitly stateful sink. Quality, sampling and restart interval are explicit
options. A successful encode is only reported after a complete EOI marker has
been emitted.

## Result and failure contract

The codec uses a structured result containing status, consumed/written byte
counts, optional frame information and a typed error. At minimum it must
distinguish invalid input, truncation, unsupported variant, resource limit,
insufficient destination and sink/source failure.

A failed decode may leave already written pixels unspecified unless the API
explicitly promises transactional output. The first public contract should
therefore either provide a preflight phase or document partial output clearly.
Limits cover encoded bytes, pixel count, component dimensions, output bytes and
workspace requirements. Arithmetic overflow is an error, never a truncation.

## Metadata and colour

The codec reports technical signalling (component IDs, sampling factors, JFIF
and Adobe markers) but does not apply colour conversion. EXIF, ICC, APP and COM
payloads are either borrowed/reported or explicitly rejected/discarded according
to a visible policy. Successful pixel decoding does not imply metadata
preservation.

## Streaming boundary

The first codec admission may use a complete borrowed JPEG byte range. A future
pull source must report exact progress, blocked/backpressure, EOF/truncation,
source failure and cancellation. Header streaming and entropy streaming are
separate capabilities; header-only pull support must not be advertised as full
streaming decode.

## TIFF integration

`imageio-d` reads TIFF strip/tile ranges and passes each complete JPEG codestream
to `compression-d`. It validates the decoded byte/component geometry against
the TIFF block before placing pixels into the requested region. TIFF Predictor,
planar configuration, tile padding and range planning remain imageio concerns.

No JPEG algorithm, DCT, Huffman table or entropy implementation is to be copied
into `imageio-d`.
