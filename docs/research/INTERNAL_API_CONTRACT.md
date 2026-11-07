# Internal API contract — research vocabulary

Status: selected research shape, not a public API. Names, modules and field
types may still change after real consumer validation and the M5 admission
gate. This document stabilizes the concepts used by the experiments so that
new format probes do not invent competing vocabulary.

## Read-side flow

```text
ImageSource -> ImageReader -> ImageInfo -> ReadArea -> ReadResult
                                            \-> ImageBuffer
```

## Naming rule

Names visible to a consumer describe an action or an image concept, not the
file-format machinery behind it. Prefer `ImageSource`, `ImageReader`,
`ImageInfo`, `ReadArea`, `ImageBuffer` and `ReadResult`. Avoid exposing names
such as `IFD`, `GeoKey`, `Block`, `Predictor`, `RangeWindow`, `DecodePath` or
`TagValue`; those belong in `imageio.internal` and test probes.

Technical field names are retained only where the consumer must make an
explicit technical choice. For example, `sampleType`, `bitsPerSample`,
`compression` and `pixelSize` are understandable image properties; they are
not codec implementation names.

`ImageSource` consumes bytes or ranges from the shared `transport-d v0.1.0`
transport/access contract. The integration probe under
`experiments/transport_consumer/` uses the same contract for a local TIFF
header and compressed payload range, then passes that range into the existing
D Deflate decoder bridge.
A source may be backed by a local file, memory or a remote provider. It owns
image-source identity and decoder-facing access only; it does not implement an
HTTP client, general download policy, OSM access or an application cache.

`ImageReader` owns inspection and read state for an opened source. Inspection
does not decode pixels. A reader may retain codec workspace, but it must not
retain a caller-owned destination after the read operation returns.

`ImageInfo` is technical and inspectable without decoding. It contains:

- dimensions, band count/order as encoded, sample type and bit depth;
- planar/chunky layout, block geometry, compression and predictor;
- technical NoData, scale and offset declarations;
- technical GeoTIFF keys and affine transform parameters;
- available overview descriptors and format capabilities.

It does not contain semantic channel bindings, colour meaning, radiometric
values, CRS domain objects, masks or an inferred RGBA model.

The preferred field groups are likewise user-oriented:

| Group | Meaning | Internal implementation terms excluded |
|---|---|---|
| `size` | image width and height | IFD entry numbers |
| `bands` | encoded band count/order and sample descriptions | tag-array offsets |
| `values` | stored sample form and bit depth | decoder word/load helpers |
| `layout` | planar/chunky arrangement and block dimensions | strip/tile table internals |
| `georeference` | technical transform and supplied CRS keys | GeoKey parser state |
| `overviews` | available reduced-resolution images | sub-IFD traversal state |
| `capabilities` | operations supported for this source | codec dispatch flags |

`ReadArea` contains an explicit pixel region, optional band selection,
representation choice and overview choice. The default research request reads
the stored values: no scaling, resampling, colour conversion or NoData policy.

`ImageBuffer` is caller-owned storage described with raster-d-compatible
dimensions, planes, strides and sample representation. An implementation may
provide an owned-result convenience path later, but its allocation and
lifetime must be explicit and it must not become a second raster storage model.

`ReadResult` reports technical execution, not image meaning:

- actual decoded coverage;
- stored-resolution, overview or full-image path;
- selected overview, if any;
- compressed bytes/ranges requested and decoded block count when available;
- technical provenance/revision information supplied by the source;
- structured failure status and whether earlier destination regions committed.

For a range-capable source, `ReadResult` may additionally report the source
work performed:

- requested range count;
- requested encoded bytes;
- bytes needed for the decoded blocks;
- amplification caused by block boundaries;
- whether the requested area required the complete source.

These are measurements, not scheduling instructions. A range source must
reject an unavailable or out-of-bounds range as a source/read error; it must
not silently replace it with a full download. HTTP retries, caching,
coalescing and cancellation belong to the shared transport/access layer and
must remain visible there rather than being hidden inside an image reader.

## Ownership and failure rules

- Source, reader, destination and result ownership are separate concepts.
- Borrowed source/destination slices are valid only for the documented call
  scope; DIP1000 probes must reject escaping views.
- `raster-d` owns retained storage, views, strides, ROIs and leases.
- Successful decode into caller-owned storage does not transfer storage
  ownership to imageio-d.
- The `@safe @nogc nothrow` core uses structured statuses/results.
- A failure must identify truncation, malformed metadata, unsupported
  representation, insufficient workspace, invalid destination or codec error.
- Partial commitment is format/operation-specific and must be reported; an
  API must not imply atomic destination writes unless preflight proves it.

## Explicitly outside the contract

`imageio-d` does not own CRS interpretation or reprojection, NoData/validity/
alpha policy, colour management, radiometric scaling, semantic band binding,
resampling policy, image processing, scheduler/cache, HTTP retry policy or
file transactionality. These belong to `imagery-d`, `color-d`, `raster-d` or
the application adapter as appropriate.

## Write-side vocabulary

The matching consumer-facing write flow is:

```text
ImageData + WriteOptions -> ImageWriter -> ImageTarget -> WriteResult
```

`WriteOptions` makes the output format, stored-value form, lossy controls and
metadata-loss policy explicit. `ImageTarget` is caller-owned output; a writer
reports bytes written, completion and known metadata loss. A failed write must
document whether the target may contain a partial result. Atomic replacement,
file cleanup and retry policy belong to the application or an explicit future
target abstraction, not to a hidden writer side effect.

## Error vocabulary

Read failures distinguish unavailable source, truncated input, invalid
metadata, unsupported values, insufficient workspace, invalid buffer and
codec failure. A read result must not claim completion after one of these
failures.

Write results distinguish `complete` and `partial`. A sink failure may leave a
partial target, and the number of bytes written is reported. Unsupported or
unrepresentable metadata is either rejected or recorded as explicitly allowed
loss; it is never silently discarded.

## Current evidence boundary

The vocabulary is exercised by research-only TIFF/GeoTIFF, range, overview,
window and raster-d handoff probes. It is not yet a public module contract:
the real consumer read-to-processing-to-write path, complete range-backed COG
decode, malformed corpus and M5 admission decision remain open.
