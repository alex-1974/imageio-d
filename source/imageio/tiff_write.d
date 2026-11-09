/** Narrow classic-TIFF writer for the release read/write gate.
 *
 * This writer emits little-endian, chunky, uncompressed classic TIFF. It
 * preserves caller-provided UInt8/UInt16 interleaved samples and does not
 * perform colour, NoData or CRS conversion. Broader TIFF write variants stay
 * unsupported until their independent gates pass.
 */
module imageio.tiff_write;

import std.algorithm.searching : canFind;
import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    ImageWriteFormat, ImageWriteRequest, MetadataDisposition, mapSinkFailure,
    writeAtomically;

struct TiffWriteInfo
{
    uint width;
    uint height;
    ubyte channels;
    ubyte sampleBytes;
    uint rowsPerStrip;
}

/** Raw technical TIFF metadata; values are copied without CRS interpretation. */
struct TiffWriteMetadata
{
    const(ubyte)[] noDataAscii;
    const(ushort)[] geoKeyDirectory;
}

struct TiffWriteRequirements
{
    ImageWriteError error = ImageWriteError.none;
    size_t rowBytes;
    size_t fileBytes;
    size_t pixelOffset;
    size_t noDataOffset;
    size_t geoKeyOffset;
    size_t stripOffsetsOffset;
    size_t stripCountsOffset;
    uint stripCount;
    @property bool valid() const @safe pure nothrow @nogc
    { return error == ImageWriteError.none; }
}

private void put16(scope ubyte[] output, size_t p, ushort value)
@safe pure nothrow @nogc
{ output[p] = cast(ubyte)value; output[p + 1] = cast(ubyte)(value >> 8); }

private void put32(scope ubyte[] output, size_t p, uint value)
@safe pure nothrow @nogc
{ put16(output, p, cast(ushort)value); put16(output, p + 2, cast(ushort)(value >> 16)); }

TiffWriteRequirements tiffWriteRequirements(TiffWriteInfo info,
    TiffWriteMetadata metadata = TiffWriteMetadata.init)
@safe pure nothrow @nogc
{
    if (info.width == 0 || info.height == 0 || info.channels < 1
        || info.channels > 4 || (info.sampleBytes != 1 && info.sampleBytes != 2))
        return TiffWriteRequirements(ImageWriteError.unsupportedRepresentation);
    const pixelBytes = cast(size_t)info.channels * info.sampleBytes;
    if (info.width > size_t.max / pixelBytes)
        return TiffWriteRequirements(ImageWriteError.outputLimitExceeded);
    const rowBytes = cast(size_t)info.width * pixelBytes;
    const rowsPerStrip = info.rowsPerStrip == 0 ? info.height : info.rowsPerStrip;
    if (rowsPerStrip == 0 || rowsPerStrip > info.height)
        return TiffWriteRequirements(ImageWriteError.unsupportedRepresentation);
    const stripCount = (info.height + rowsPerStrip - 1) / rowsPerStrip;
    const baseEntries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    const entries = baseEntries + (metadata.noDataAscii.length != 0 ? 1U : 0U)
        + (metadata.geoKeyDirectory.length != 0 ? 1U : 0U);
    const ifdEnd = 8 + 2 + entries * 12 + 4;
    const bitsBytes = info.channels > 2 ? info.channels * 2U : 0U;
    const stripOffsetsOffset = ifdEnd + bitsBytes;
    const stripCountsOffset = stripOffsetsOffset + stripCount * 4;
    const noDataOffset = metadata.noDataAscii.length != 0
        ? stripCountsOffset + stripCount * 4 : 0;
    const geoKeyOffset = noDataOffset != 0
        ? noDataOffset + metadata.noDataAscii.length + 1
        : metadata.geoKeyDirectory.length != 0
            ? stripCountsOffset + stripCount * 4 : 0;
    const metadataBytes = (metadata.noDataAscii.length != 0
        ? metadata.noDataAscii.length + 1 : 0)
        + (metadata.geoKeyDirectory.length * 2);
    const pixelOffset = stripCountsOffset + stripCount * 4 + metadataBytes;
    const pixelTotal = cast(size_t)info.height * rowBytes;
    if (pixelOffset > size_t.max - pixelTotal
        || pixelOffset + pixelTotal > uint.max)
        return TiffWriteRequirements(ImageWriteError.outputLimitExceeded);
    return TiffWriteRequirements(ImageWriteError.none, rowBytes,
        pixelOffset + pixelTotal, pixelOffset, noDataOffset, geoKeyOffset,
        stripOffsetsOffset, stripCountsOffset, stripCount);
}

private void entry(scope ubyte[] output, ref size_t p, ushort tag, ushort kind,
    uint count, uint value) @safe pure nothrow @nogc
{
    put16(output, p, tag); put16(output, p + 2, kind);
    put32(output, p + 4, count); put32(output, p + 8, value); p += 12;
}

private void encodeClassicTiff(TiffWriteInfo info, TiffWriteMetadata metadata,
    scope const(ubyte)[] source, size_t rowStride, scope ubyte[] output,
    TiffWriteRequirements req)
@safe pure nothrow @nogc
{
    output[0 .. req.fileBytes] = 0;
    output[0] = 'I'; output[1] = 'I'; put16(output, 2, 42); put32(output, 4, 8);
    const baseEntries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    const entries = baseEntries + (metadata.noDataAscii.length != 0 ? 1U : 0U)
        + (metadata.geoKeyDirectory.length != 0 ? 1U : 0U);
    put16(output, 8, cast(ushort)entries); size_t p = 10;
    const bits = cast(uint)info.sampleBytes * 8;
    const bitsOffset = 8 + 2 + entries * 12 + 4;
    entry(output, p, 256, 4, 1, info.width); entry(output, p, 257, 4, 1, info.height);
    entry(output, p, 258, 3, info.channels,
        info.channels == 1 ? bits : info.channels == 2 ? bits | (bits << 16)
        : cast(uint)bitsOffset);
    entry(output, p, 259, 3, 1, 1);
    entry(output, p, 262, 3, 1, info.channels <= 2 ? 1U : 2U);
    entry(output, p, 273, 4, req.stripCount,
        req.stripCount == 1 ? cast(uint)req.pixelOffset
            : cast(uint)req.stripOffsetsOffset);
    const rowsPerStrip = info.rowsPerStrip == 0 ? info.height : info.rowsPerStrip;
    entry(output, p, 277, 3, 1, info.channels);
    entry(output, p, 278, 4, 1, rowsPerStrip);
    entry(output, p, 279, 4, req.stripCount,
        req.stripCount == 1 ? cast(uint)(req.rowBytes * info.height)
            : cast(uint)req.stripCountsOffset);
    entry(output, p, 284, 3, 1, 1);
    if (info.channels == 2 || info.channels == 4)
        entry(output, p, 338, 3, 1, 2);
    if (metadata.geoKeyDirectory.length != 0)
        entry(output, p, 34735, 3, cast(uint)metadata.geoKeyDirectory.length,
            cast(uint)req.geoKeyOffset);
    if (metadata.noDataAscii.length != 0)
        entry(output, p, 42113, 2, cast(uint)(metadata.noDataAscii.length + 1),
            cast(uint)req.noDataOffset);
    put32(output, p, 0);
    foreach (uint strip; 0 .. req.stripCount)
    {
        const firstRow = cast(size_t)strip * rowsPerStrip;
        const rows = (firstRow + rowsPerStrip > info.height)
            ? info.height - firstRow : rowsPerStrip;
        put32(output, req.stripOffsetsOffset + strip * 4,
            cast(uint)(req.pixelOffset + firstRow * req.rowBytes));
        put32(output, req.stripCountsOffset + strip * 4,
            cast(uint)(rows * req.rowBytes));
    }
    if (info.channels > 2)
        foreach (size_t i; 0 .. info.channels) put16(output, bitsOffset + i * 2, cast(ushort)bits);
    if (metadata.noDataAscii.length != 0)
    {
        output[req.noDataOffset .. req.noDataOffset + metadata.noDataAscii.length] =
            metadata.noDataAscii;
        output[req.noDataOffset + metadata.noDataAscii.length] = 0;
    }
    if (metadata.geoKeyDirectory.length != 0)
        foreach (size_t i; 0 .. metadata.geoKeyDirectory.length)
            put16(output, req.geoKeyOffset + i * 2, metadata.geoKeyDirectory[i]);
    foreach (size_t y; 0 .. info.height)
        output[req.pixelOffset + y * req.rowBytes .. req.pixelOffset + (y + 1) * req.rowBytes] =
            source[y * rowStride .. y * rowStride + req.rowBytes];
}

/** Encode the qualified classic-TIFF subset into a caller-owned sink. */
ImageWriteResult writeClassicTiff(ByteSink sink, TiffWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init,
    TiffWriteMetadata metadata = TiffWriteMetadata.init) @safe
{
    auto req = tiffWriteRequirements(info, metadata);
    if (!req.valid) return ImageWriteResult(req.error);
    if (rowStride < req.rowBytes || (info.height > 1
        && rowStride > (size_t.max - req.rowBytes) / (info.height - 1))
        || cast(size_t)(info.height - 1) * rowStride + req.rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    if (req.fileBytes > options.maximumOutputBytes)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto encoded = new ubyte[](req.fileBytes);
    encodeClassicTiff(info, metadata, source, rowStride, encoded, req);
    auto written = sink.write(encoded[]);
    if (written.hasError) return mapSinkFailure(written.error().bytesWritten, written.error().kind);
    if (written.value().bytesWritten != encoded.length)
        return ImageWriteResult(ImageWriteError.sinkFailure, written.value().bytesWritten);
    const hasMetadata = metadata.noDataAscii.length != 0
        || metadata.geoKeyDirectory.length != 0;
    return ImageWriteResult(ImageWriteError.none, encoded.length,
        hasMetadata ? MetadataDisposition.preserved : MetadataDisposition.notApplicable);
}

/** Atomically write the bounded classic-TIFF subset to a filesystem path. */
ImageWriteResult writeClassicTiffFile(string path, TiffWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init,
    TiffWriteMetadata metadata = TiffWriteMetadata.init) @safe
{
    return writeAtomically(path, (ByteSink sink) @safe {
        return writeClassicTiff(sink, info, source, rowStride, options, metadata);
    });
}

/** Format-neutral bounded writer entry point. */
ImageWriteResult writeImage(ByteSink sink, ImageWriteRequest request,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    if (request.format != ImageWriteFormat.tiff)
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    return writeClassicTiff(sink,
        TiffWriteInfo(request.width, request.height, request.channels,
            request.sampleBytes, request.rowsPerStrip), request.source,
        request.rowStride, options);
}

/** Format-neutral bounded writer entry point with atomic file publication. */
ImageWriteResult writeImageFile(string path, ImageWriteRequest request,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    return writeAtomically(path, (ByteSink sink) @safe {
        return writeImage(sink, request, options);
    });
}

version (unittest)
{
    @safe unittest
    {
        import std.file : read, write, remove;
        import std.path : buildPath;
        auto path = buildPath("/tmp", "imageio-d-atomic-tiff-test.tif");
        scope (exit) remove(path);
        write(path, cast(const(ubyte)[])[0xaa, 0x55]);
        ubyte[4] pixels = [1, 2, 3, 4];
        auto result = writeClassicTiffFile(path, TiffWriteInfo(2, 2, 1, 1),
            pixels[], 2);
        assert(result.complete);
        auto bytes = cast(const(ubyte)[]) read(path);
        assert(bytes.length > 8 && bytes[0] == 'I' && bytes[1] == 'I');
    }

    @safe unittest
    {
        import transport : MemorySink;
        ubyte[4] pixels = [1, 2, 3, 4];
        auto sink = new MemorySink();
        auto result = writeClassicTiff(sink, TiffWriteInfo(2, 2, 1, 1),
            pixels[], 2);
        assert(result.complete);
        assert(result.bytesWritten == sink.data.length);
        assert(sink.data.length == tiffWriteRequirements(
            TiffWriteInfo(2, 2, 1, 1)).fileBytes);
        assert(sink.data[0 .. 4] == cast(const(ubyte)[])[
            cast(ubyte)'I', cast(ubyte)'I', 42, 0]);
    }

    @safe unittest
    {
        import transport : ByteSink, WriteError, WriteFailure, WriteLimits,
            WriteResult;
        class FailingSink : ByteSink
        {
            size_t accepted;
            this(size_t accepted) @safe { this.accepted = accepted; }
            WriteResult write(scope const(ubyte)[] source,
                WriteLimits limits = WriteLimits.init) @safe
            {
                return WriteResult.failure(WriteFailure(
                    WriteError.destinationFailure,
                    accepted < source.length ? accepted : source.length));
            }
        }
        ubyte[1] pixel = [7];
        auto result = writeClassicTiff(new FailingSink(9),
            TiffWriteInfo(1, 1, 1, 1), pixel[], 1);
        assert(result.error == ImageWriteError.sinkFailure);
        assert(result.bytesWritten == 9);
    }

    @safe unittest
    {
        import transport : MemorySink;
        ubyte[1] pixel = [7];
        immutable ushort[4] keys = [1, 1, 0, 0];
        auto sink = new MemorySink();
        auto result = writeClassicTiff(sink, TiffWriteInfo(1, 1, 1, 1),
            pixel[], 1, ImageWriteOptions.init,
            TiffWriteMetadata(cast(const(ubyte)[])"-9999", keys[]));
        assert(result.complete);
        assert(result.metadata == MetadataDisposition.preserved);
        assert(sink.data.canFind(cast(const(ubyte)[])"-9999"));
        assert(sink.data.canFind(cast(const(ubyte)[])[1, 0]));
    }
}
