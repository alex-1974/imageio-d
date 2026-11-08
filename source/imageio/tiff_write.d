/** Narrow classic-TIFF writer for the release read/write gate.
 *
 * This writer emits little-endian, chunky, uncompressed classic TIFF. It
 * preserves caller-provided UInt8/UInt16 interleaved samples and does not
 * perform colour, NoData or CRS conversion. Broader TIFF write variants stay
 * unsupported until their independent gates pass.
 */
module imageio.tiff_write;

import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, mapSinkFailure;

struct TiffWriteInfo { uint width; uint height; ubyte channels; ubyte sampleBytes; }

struct TiffWriteRequirements
{
    ImageWriteError error = ImageWriteError.none;
    size_t rowBytes;
    size_t fileBytes;
    size_t pixelOffset;
    @property bool valid() const @safe pure nothrow @nogc
    { return error == ImageWriteError.none; }
}

private void put16(scope ubyte[] output, size_t p, ushort value)
@safe pure nothrow @nogc
{ output[p] = cast(ubyte)value; output[p + 1] = cast(ubyte)(value >> 8); }

private void put32(scope ubyte[] output, size_t p, uint value)
@safe pure nothrow @nogc
{ put16(output, p, cast(ushort)value); put16(output, p + 2, cast(ushort)(value >> 16)); }

TiffWriteRequirements tiffWriteRequirements(TiffWriteInfo info)
@safe pure nothrow @nogc
{
    if (info.width == 0 || info.height == 0 || info.channels < 1
        || info.channels > 4 || (info.sampleBytes != 1 && info.sampleBytes != 2))
        return TiffWriteRequirements(ImageWriteError.unsupportedRepresentation);
    const pixelBytes = cast(size_t)info.channels * info.sampleBytes;
    if (info.width > size_t.max / pixelBytes)
        return TiffWriteRequirements(ImageWriteError.outputLimitExceeded);
    const rowBytes = cast(size_t)info.width * pixelBytes;
    const entries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    const ifdEnd = 8 + 2 + entries * 12 + 4;
    const bitsBytes = info.channels > 2 ? info.channels * 2U : 0U;
    const pixelOffset = ifdEnd + bitsBytes;
    const pixelTotal = cast(size_t)info.height * rowBytes;
    if (pixelOffset > size_t.max - pixelTotal
        || pixelOffset + pixelTotal > uint.max)
        return TiffWriteRequirements(ImageWriteError.outputLimitExceeded);
    return TiffWriteRequirements(ImageWriteError.none, rowBytes,
        pixelOffset + pixelTotal, pixelOffset);
}

private void entry(scope ubyte[] output, ref size_t p, ushort tag, ushort kind,
    uint count, uint value) @safe pure nothrow @nogc
{
    put16(output, p, tag); put16(output, p + 2, kind);
    put32(output, p + 4, count); put32(output, p + 8, value); p += 12;
}

private void encodeClassicTiff(TiffWriteInfo info, scope const(ubyte)[] source,
    size_t rowStride, scope ubyte[] output, TiffWriteRequirements req)
@safe pure nothrow @nogc
{
    output[0 .. req.fileBytes] = 0;
    output[0] = 'I'; output[1] = 'I'; put16(output, 2, 42); put32(output, 4, 8);
    const entries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    put16(output, 8, cast(ushort)entries); size_t p = 10;
    const bits = cast(uint)info.sampleBytes * 8;
    const bitsOffset = 8 + 2 + entries * 12 + 4;
    entry(output, p, 256, 4, 1, info.width); entry(output, p, 257, 4, 1, info.height);
    entry(output, p, 258, 3, info.channels,
        info.channels == 1 ? bits : info.channels == 2 ? bits | (bits << 16)
        : cast(uint)bitsOffset);
    entry(output, p, 259, 3, 1, 1);
    entry(output, p, 262, 3, 1, info.channels <= 2 ? 1U : 2U);
    entry(output, p, 273, 4, 1, cast(uint)req.pixelOffset);
    entry(output, p, 277, 3, 1, info.channels); entry(output, p, 278, 4, 1, info.height);
    entry(output, p, 279, 4, 1, cast(uint)(req.rowBytes * info.height));
    entry(output, p, 284, 3, 1, 1);
    if (entries == 11) entry(output, p, 338, 3, 1, 2);
    put32(output, p, 0);
    if (info.channels > 2)
        foreach (size_t i; 0 .. info.channels) put16(output, bitsOffset + i * 2, cast(ushort)bits);
    foreach (size_t y; 0 .. info.height)
        output[req.pixelOffset + y * req.rowBytes .. req.pixelOffset + (y + 1) * req.rowBytes] =
            source[y * rowStride .. y * rowStride + req.rowBytes];
}

/** Encode the qualified classic-TIFF subset into a caller-owned sink. */
ImageWriteResult writeClassicTiff(ByteSink sink, TiffWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    auto req = tiffWriteRequirements(info);
    if (!req.valid) return ImageWriteResult(req.error);
    if (rowStride < req.rowBytes || (info.height > 1
        && rowStride > (size_t.max - req.rowBytes) / (info.height - 1))
        || cast(size_t)(info.height - 1) * rowStride + req.rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    if (req.fileBytes > options.maximumOutputBytes)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto encoded = new ubyte[](req.fileBytes); encodeClassicTiff(info, source, rowStride, encoded, req);
    auto written = sink.write(encoded[]);
    if (written.hasError) return mapSinkFailure(written.error().bytesWritten, written.error().kind);
    if (written.value().bytesWritten != encoded.length)
        return ImageWriteResult(ImageWriteError.sinkFailure, written.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none, encoded.length, MetadataDisposition.notApplicable);
}

version (unittest)
{
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
}
