/** PNG writer foundation for the full PNG Read/Write gate. */
module imageio.png_write;

import compression.core : DecodeStatus;
import compression.encode : encodeZlibStored, zlibStoredSize;
import compression.checksum : crc32;
import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, MetadataPolicy, mapSinkFailure;

struct PngWriteInfo
{
    uint width;
    uint height;
    ubyte bitDepth = 8;
    ubyte colorType = 2;
    bool hasAncillary;
    const(ubyte)[] palette;
}

private ubyte channels(ubyte colorType) @safe pure nothrow @nogc
{
    final switch (colorType) { case 0: return 1; case 2: return 3; case 3: return 1;
        case 4: return 2; case 6: return 4; }
}

private void put32(scope ubyte[] bytes, size_t p, uint value)
@safe pure nothrow @nogc
{
    bytes[p] = cast(ubyte)(value >> 24); bytes[p + 1] = cast(ubyte)(value >> 16);
    bytes[p + 2] = cast(ubyte)(value >> 8); bytes[p + 3] = cast(ubyte)value;
}

private size_t chunk(scope ubyte[] output, size_t p, scope const(ubyte)[] type,
    scope const(ubyte)[] data) @safe pure nothrow @nogc
{
    put32(output, p, cast(uint)data.length); output[p + 4 .. p + 8] = type;
    output[p + 8 .. p + 8 + data.length] = data;
    put32(output, p + 8 + data.length, crc32(output[p + 4 .. p + 8 + data.length]));
    return p + 12 + data.length;
}

/** Encode non-interlaced 8/16-bit gray, RGB and alpha PNG into a sink.
 *
 * This is intentionally a real package entry point, but the PNG gate remains
 * open until indexed/packed/interlaced paths and metadata transfer are added.
 */
ImageWriteResult writePng(ByteSink sink, PngWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    const validDepth = info.colorType == 0
        ? (info.bitDepth == 1 || info.bitDepth == 2 || info.bitDepth == 4
            || info.bitDepth == 8 || info.bitDepth == 16)
        : info.colorType == 3
            ? (info.bitDepth == 1 || info.bitDepth == 2 || info.bitDepth == 4
                || info.bitDepth == 8)
            : (info.bitDepth == 8 || info.bitDepth == 16);
    if (info.width == 0 || info.height == 0 || !validDepth
        || (info.colorType != 0 && info.colorType != 2
            && info.colorType != 3 && info.colorType != 4 && info.colorType != 6))
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    if (info.colorType == 3 && (info.palette.length == 0
        || info.palette.length % 3 != 0 || info.palette.length > 256 * 3))
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    if (info.hasAncillary && options.metadata != MetadataPolicy.allowLoss)
        return ImageWriteResult(ImageWriteError.metadataRejected);
    const rowBits = cast(size_t)info.width * channels(info.colorType) * info.bitDepth;
    const rowBytes = (rowBits + 7) / 8;
    if (rowStride < rowBytes || cast(size_t)(info.height - 1) * rowStride
        + rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    const filteredBytes = cast(size_t)info.height * (rowBytes + 1);
    const zlibCapacity = zlibStoredSize(filteredBytes);
    if (zlibCapacity > options.maximumOutputBytes || zlibCapacity > uint.max - 57)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto filtered = new ubyte[](filteredBytes);
    foreach (size_t y; 0 .. info.height)
    {
        filtered[y * (rowBytes + 1)] = 0;
        filtered[y * (rowBytes + 1) + 1 .. (y + 1) * (rowBytes + 1)] =
            source[y * rowStride .. y * rowStride + rowBytes];
    }
    auto zlib = new ubyte[](zlibCapacity);
    auto encoded = encodeZlibStored(filtered[], zlib[]);
    if (encoded.status != DecodeStatus.done)
        return ImageWriteResult(ImageWriteError.sourceFailure);
    const paletteBytes = info.colorType == 3 ? 12 + info.palette.length : 0;
    auto output = new ubyte[](57 + encoded.produced + paletteBytes);
    output[0 .. 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    ubyte[13] ihdr; put32(ihdr[], 0, info.width); put32(ihdr[], 4, info.height);
    ihdr[8] = info.bitDepth; ihdr[9] = info.colorType;
    auto p = chunk(output, 8, cast(const(ubyte)[])"IHDR", ihdr[]);
    if (info.colorType == 3)
        p = chunk(output, p, cast(const(ubyte)[])"PLTE", info.palette);
    p = chunk(output, p, cast(const(ubyte)[])"IDAT", zlib[0 .. encoded.produced]);
    chunk(output, p, cast(const(ubyte)[])"IEND", null);
    auto written = sink.write(output[]);
    if (written.hasError) return mapSinkFailure(written.error().bytesWritten, written.error().kind);
    if (written.value().bytesWritten != output.length)
        return ImageWriteResult(ImageWriteError.sinkFailure, written.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none, output.length,
        info.hasAncillary ? MetadataDisposition.discarded : MetadataDisposition.notApplicable);
}

version (unittest)
{
    @safe unittest
    {
        import transport : MemorySink;
        ubyte[6] pixels = [255, 0, 0, 0, 255, 0];
        auto sink = new MemorySink();
        auto result = writePng(sink, PngWriteInfo(2, 1, 8, 2), pixels[], 6,
            ImageWriteOptions(MetadataPolicy.allowLoss, 4096));
        assert(result.complete);
        assert(sink.data.length == result.bytesWritten);
        assert(sink.data[0 .. 8] == cast(const(ubyte)[])[137, 80, 78, 71, 13, 10, 26, 10]);
    }

    @safe unittest
    {
        import transport : MemorySink;
        // Four 2-bit palette indices packed into one byte.
        ubyte[1] pixels = [0b00_01_10_11];
        auto sink = new MemorySink();
        auto result = writePng(sink,
            PngWriteInfo(4, 1, 2, 3, false,
                [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]),
            pixels[], 1, ImageWriteOptions(MetadataPolicy.allowLoss, 4096));
        assert(result.complete);
        assert(sink.data.length == result.bytesWritten);
        // Signature, IHDR, PLTE, IDAT, IEND; PLTE starts after the IHDR chunk.
        assert(sink.data[37 .. 41] == cast(const(ubyte)[])"PLTE");
    }

    @safe unittest
    {
        import transport : ByteSink, WriteError, WriteFailure, WriteLimits,
            WriteResult, WriteValue;
        class FailingSink : ByteSink
        {
            size_t accepted;
            this(size_t accepted) @safe { this.accepted = accepted; }
            WriteResult write(scope const(ubyte)[] source,
                WriteLimits limits = WriteLimits.init) @safe
            {
                const count = accepted < source.length ? accepted : source.length;
                return WriteResult.failure(WriteFailure(
                    WriteError.destinationFailure, count));
            }
        }
        ubyte[3] pixels = [255, 0, 0];
        auto result = writePng(new FailingSink(5), PngWriteInfo(1, 1, 8, 2),
            pixels[], 3);
        assert(result.error == ImageWriteError.sinkFailure);
        assert(result.bytesWritten == 5);
    }
}
