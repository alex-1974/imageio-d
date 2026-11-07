# Read/write API boundary experiment

Status: consumer-shaped research only. No real editor or `dunia` integration
is currently possible. These sketches are not accepted public names.

## Two candidate call shapes

1. Stateful `Reader.inspect/readInto` and `Writer.writeFrom`: explicit opened
   source/destination lifetime and reusable codec workspace. The caller
   selects technical representation, format/options and metadata-loss policy;
   storage remains a `raster-d` view. Avoid a monolithic `Image` object.
2. Stateless `inspect/decodeInto/encodeInto` on borrowed encoded byte slices
   and caller-owned destinations: minimal allocation, `@nogc` kernel and easy
   unit tests, but file/stream lifetime, format dispatch and large-image
   streaming must be handled outside this call shape.

The PNG probe implements the second, byte-slice kernel form plus a pull-style
row writer. The original decoder takes caller-owned compressed/filtered
full-image scratch; `decodePngRows` takes two row buffers and consumes IDAT
slices from the complete borrowed file. `StoredRowWriter` takes one source row
per call and emits one IDAT chunk to caller-owned output, which can then be
flushed. `png_api_probe.d` proves these signatures compile in
`@safe pure nothrow @nogc` code. It does **not** establish `raster-d` view
compatibility or D-idiomatic public naming. Pixel-strided/planar views are
not directly consumed, so an adapter might copy; count that copy before API
admission.

## Owner and failure checks

- `imageio-d`: encoded bytes, format mechanics, inspection, codec, technical
  shape and metadata/loss reporting. No radiometry, colour correction, alpha
  policy, CRS interpretation or application cache.
- `raster-d`: destination/source memory, views, strides, ROI and leases. An
  imageio reader/writer must borrow rather than retain a view without an
  explicit ownership contract.
- `color-d`: colour mathematics invoked only when the caller requests it.
- `imagery-d`: semantic channel/NoData/alpha bindings and processing. Its
  generated/non-file image path bypasses imageio.
- Application/adapter: opens a source, chooses format, processing and export
  representation, and decides whether metadata loss is acceptable.

The JPEG RGB8 read/write experiment currently includes an RGB↔YCbCr
convenience transform so that independent image decoders can serve as oracles.
It is not an accepted boundary: the JPEG format core should expose native
component planes and sampling/marker metadata, while a requested RGB view or
RGB-derived save path is an explicit `color-d`/application adapter choice.
See `JPEG_COLOR_BOUNDARY.md` and `JPEG_SOURCE_SINK_CONTRACT.md`.

For a writer, success must state bytes emitted and metadata dropped. A future
file sink must specify whether failure leaves a partial file and whether
atomic replacement is promised; the current byte-slice kernel preflights
capacity and does not solve file transactionality. The pull-style writer
preflights each row call but cannot undo chunks a caller already sent to a
sink. Row decode may commit complete preceding rows before a late zlib/filter
failure, reported through `written`; the full-staging decoder preserves the
destination on decode failure. For a reader, inspection
must not imply decoding, and unsupported variants must fail distinctly.
The row writer can be abandoned between calls by discarding its caller-owned
state; a previously flushed sink is then partial and the application must
decide cleanup/atomic replacement. The current synchronous row decoder has
no in-call cancellation hook; a future source/decoder state API must make
that boundary explicit before promising cancellable large reads.

## Admission questions still open

- Which names/modules let the real consumers express both directions with
  minimal ceremony and no hidden allocations or conversions?
- Can native samples transfer directly through actual `raster-d` views and
  leases, including row/pixel strides and retained-result lifetime?
- How should technical metadata be retained as an owned value so a writer can
  preserve safe chunks, versus an explicit loss report for unsupported data?
- Which streaming source/sink shape supports large PNG/TIFF and cancellation
  without importing a general scheduler or cache into imageio?

Do not count the compile-only PNG probe or isolated imagery materialization
probe as a real consumer test. Keep the M5 public API gate open.
