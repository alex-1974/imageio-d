/** BigTIFF writer for uncompressed chunky UInt8/UInt16 strips. */
module imageio.tiff_big_write;

import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, mapSinkFailure;
import imageio.tiff_write : TiffWriteInfo;

private void put16(scope ubyte[] b, size_t p, ushort v)
@safe pure nothrow @nogc
{ b[p] = cast(ubyte)v; b[p + 1] = cast(ubyte)(v >> 8); }

private void put64(scope ubyte[] b, size_t p, ulong v)
@safe pure nothrow @nogc
{
    foreach (size_t i; 0 .. 8) b[p + i] = cast(ubyte)(v >> (i * 8));
}

private void entry(scope ubyte[] b, ref size_t p, ushort tag, ushort type,
    ulong count, ulong value) @safe pure nothrow @nogc
{
    put16(b, p, tag); put16(b, p + 2, type); put64(b, p + 4, count);
    put64(b, p + 12, value); p += 20;
}

/** Write a little-endian BigTIFF with uncompressed chunky strips. */
ImageWriteResult writeBigTiff(ByteSink sink, TiffWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    if (info.width == 0 || info.height == 0 || info.channels < 1
        || info.channels > 4 || (info.sampleBytes != 1 && info.sampleBytes != 2))
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    const rowsPerStrip = info.rowsPerStrip == 0 ? info.height : info.rowsPerStrip;
    if (rowsPerStrip == 0 || rowsPerStrip > info.height)
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    const rowBytes = cast(size_t)info.width * info.channels * info.sampleBytes;
    if (rowStride < rowBytes || cast(size_t)(info.height - 1) * rowStride
        + rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    const strips = (info.height + rowsPerStrip - 1) / rowsPerStrip;
    const entries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    const ifdEnd = 16 + 8 + entries * 20 + 8;
    const bitsBytes = 0U; // up to four SHORT values fit BigTIFF's 8-byte value field
    const offsetsTable = ifdEnd + bitsBytes;
    const countsTable = offsetsTable + strips * 8;
    const pixels = countsTable + strips * 8;
    const totalPixels = cast(size_t)info.height * rowBytes;
    if (pixels > size_t.max - totalPixels
        || pixels + totalPixels > options.maximumOutputBytes)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto output = new ubyte[](pixels + totalPixels);
    output[0] = 'I'; output[1] = 'I'; put16(output, 2, 43);
    put16(output, 4, 8); put16(output, 6, 0); put64(output, 8, 16);
    put64(output, 16, entries);
    size_t p = 24;
    const bits = info.sampleBytes * 8;
    entry(output, p, 256, 16, 1, info.width);
    entry(output, p, 257, 16, 1, info.height);
    ulong bitsValue;
    foreach (size_t i; 0 .. info.channels)
        bitsValue |= cast(ulong)bits << (i * 16);
    entry(output, p, 258, 3, info.channels, bitsValue);
    entry(output, p, 259, 3, 1, 1);
    entry(output, p, 262, 3, 1, info.channels <= 2 ? 1 : 2);
    entry(output, p, 273, 16, strips, strips == 1 ? pixels : offsetsTable);
    entry(output, p, 277, 3, 1, info.channels);
    entry(output, p, 278, 16, 1, rowsPerStrip);
    entry(output, p, 279, 16, strips,
        strips == 1 ? cast(ulong)rowBytes * info.height : countsTable);
    entry(output, p, 284, 3, 1, 1);
    if (entries == 11) entry(output, p, 338, 3, 1, 2);
    put64(output, p, 0);
    foreach (ulong strip; 0 .. strips)
    {
        const first = cast(size_t)strip * rowsPerStrip;
        const rows = first + rowsPerStrip > info.height
            ? info.height - first : rowsPerStrip;
        const offset = pixels + first * rowBytes;
        put64(output, offsetsTable + strip * 8, offset);
        put64(output, countsTable + strip * 8, cast(ulong)rows * rowBytes);
    }
    foreach (size_t y; 0 .. info.height)
        output[pixels + y * rowBytes .. pixels + (y + 1) * rowBytes] =
            source[y * rowStride .. y * rowStride + rowBytes];
    auto written = sink.write(output[]);
    if (written.hasError)
        return mapSinkFailure(written.error().bytesWritten, written.error().kind);
    if (written.value().bytesWritten != output.length)
        return ImageWriteResult(ImageWriteError.sinkFailure,
            written.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none, output.length,
        MetadataDisposition.notApplicable);
}
