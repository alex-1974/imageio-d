# API-fit experiment — initial sketches

Status: research only. These are competing sketches, not public API.
Real consumer tests are currently unavailable; sketches and isolated compile
probes are surrogate evidence, not application validation.

The examples deliberately use familiar D and workspace vocabulary. The
experiment compares readability, imports, ownership visibility, error paths,
and the amount of accidental image semantics.

## Flow A — inspect without decoding

```d
import imageio.source : openFile;

auto reader = openFile("scene.tif");
scope (exit) reader.close();
const info = reader.inspect();
assert(info.width > 0);
```

Questions: Is an explicit `Reader` needed? Is `scope` sufficient? Can `Info`
outlive the reader? What is the error form?

## Flow B — explicit native region

```d
import imageio.decode : ReadRequest;
import imageio.region : Region;

auto request = ReadRequest.native(Region(1024, 2048, 512, 512));
auto decoded = reader.read(request);
```

Questions: How are bands, layout, destination and capabilities expressed?
Does `native` clearly mean no scaling or colour conversion?

## Flow C — caller-owned destination

```d
auto destination = rasterStorage!ushort(region);
auto result = reader.readInto(request, destination.view);
```

Questions: Can the type prove that the decoder does not retain the view? Can
the result expose exact coverage and stride without introducing a second
storage model?

## Flow D — explicit conversion

```d
auto request = ReadRequest.converted(
    region,
    SampleRepresentation.float32,
    ConversionPolicy.noColourManagement
);
```

Questions: Are conversion, scaling, resampling and colour interpretation
separate options? Is the API resistant to accidental normalisation?

## Flow E — technical metadata to imagery semantics

```d
const technical = reader.inspect();
auto productPlan = imageryPlan.fromTechnical(
    technical,
    channelBindings
);
```

Questions: Is the boundary clear enough that `imageio-d` never decides that
four channels mean RGBA or that a NoData value is alpha?

## Flow F — explicit export after image processing

```text
imagery result + caller-chosen representation and metadata policy
    -> raster-d readable view
    -> imageio-d encoder for a declared format/variant
    -> caller-owned destination or file
    -> structured write result and provenance/loss report
```

Questions: How does the caller select JPEG/PNG/TIFF capabilities and options
without an all-purpose flag bag? Which technical metadata can be preserved,
which is dropped, and how is loss reported before writing? Does a failed
write leave a partial file, and who owns cleanup? Where are file writes
atomic, if promised? Format-required codec transforms are not a license for
implicit colour management, radiometry or semantic channel binding.

Review this flow separately with a general editor, a scientific high-depth
image and the `dunia` satellite workflow. No names or code above are public.

## Evaluation rubric

Score each sketch from 0 (poor) to 3 (strong):

- D naming and module ergonomics;
- ownership/lifetime visibility;
- compatibility with `raster-d` vocabulary;
- no implicit colour/radiometric semantics;
- native sample fidelity;
- error-path clarity;
- room for memory, file and stream sources;
- capability and cost visibility.
- encode options, partial-write and metadata-loss clarity.

The selected shape must be tested with DMD and LDC compile probes, including
negative lifetime cases, before any public module is admitted.

## Selected naming direction

The preferred consumer-facing sketch uses image concepts and actions. A caller
should not need to know whether the source is TIFF, GeoTIFF, PNG or COG to read
stored values:

```d
import imageio;

auto source = ImageSource.fromFile("scene.tif");
auto reader = ImageReader.open(source);
const info = reader.info();

auto area = ReadArea(1024, 2048, 512, 512);
auto result = reader.readInto(area, imageBuffer);
assert(result.coverage.contains(area));
```

For a remote or sparse source, the source selection remains understandable and
the transport detail stays behind the source boundary:

```d
auto source = ImageSource.fromRanges(rangeProvider);
auto reader = ImageReader.open(source);
auto result = reader.readInto(ReadArea(100, 200, 32, 24), imageBuffer);
```

The result may expose facts a caller needs for cost and correctness, using
plain image language:

```d
assert(result.valuesAreStoredValues);
assert(result.readPath == ReadPath.storedBlocks);
assert(result.decodedArea == requestedArea);
```

`IFD`, `GeoKey`, `TagValue`, `Predictor`, `RangeWindow` and similar names do
not appear in these calls. They remain internal parser, codec and diagnostic
terms. This sketch is still research-only; the actual field types and module
exports require real-consumer validation.
