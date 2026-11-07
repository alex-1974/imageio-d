# Error contract

Imageio errors describe the image-I/O boundary. They do not replace the
underlying transport or compression diagnostics.

## Detection and inspection

- `unsupportedFormat` means the byte signature is not a supported image
  format;
- `invalidByteOrder` or `invalidMagic` means a TIFF-like header is malformed;
- `invalidRange` means a referenced region or offset cannot be represented;
- `truncated` means the source ended before the required header, IFD, block or
  decoded payload was complete;
- `sourceFailure` means the transport source failed without a more specific
  image-format diagnosis;
- `unsupportedLayout` means the format is recognized but its layout or
  representation is outside the admitted decoder gate.

## Result preservation

Consumers must inspect `ok`/`error` before using `header`, `info`, `plan` or
`region`. Failed results do not promise meaningful output fields.

## No silent fallback

An exact range failure must not trigger a full-resource read. A requested
window that cannot be served by the admitted decoder path must fail or be
reported as an explicitly different decode path; it must not silently claim a
cheap window read.

## Transport boundary

Transport errors remain transport-d responsibilities. Imageio maps them only
at the image boundary and retains the distinction between incomplete input,
unavailable ranges and unsupported image layout where the evidence allows it.
