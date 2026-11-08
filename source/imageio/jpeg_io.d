/** JPEG Read/Write adapter using the released compression-d codec contract. */
module imageio.jpeg_io;

import compression.jpeg : Info, Limits, EncodeOptions, Sampling, Result,
    encodeJpeg, decodeJpeg, Status, EncodeMetadata,
    JpegMetadataPolicy = MetadataPolicy;
import transport : ByteSink;
import imageio.io : ImageReadError, ImageReadResult, ImageWriteError,
    ImageWriteOptions, ImageWriteResult, MetadataDisposition, MetadataPolicy,
    mapSinkFailure;

private ImageWriteError mapWrite(Status status) @safe pure nothrow @nogc
{
    final switch (status)
    {
        case Status.ok: return ImageWriteError.none;
        case Status.unsupported: return ImageWriteError.unsupportedRepresentation;
        case Status.invalid: return ImageWriteError.unsupportedRepresentation;
        case Status.limit: return ImageWriteError.outputLimitExceeded;
        case Status.destinationTooSmall: return ImageWriteError.sinkFailure;
        case Status.truncated: return ImageWriteError.truncatedInput;
    }
}

private ImageReadError mapRead(Status status) @safe pure nothrow @nogc
{
    final switch (status)
    {
        case Status.ok: return ImageReadError.none;
        case Status.invalid: return ImageReadError.malformedInput;
        case Status.truncated: return ImageReadError.truncatedInput;
        case Status.unsupported: return ImageReadError.unsupportedRepresentation;
        case Status.limit: return ImageReadError.sizeLimit;
        case Status.destinationTooSmall: return ImageReadError.sizeLimit;
    }
}

struct JpegWriteInfo
{
    uint width;
    uint height;
    ubyte components = 3;
}

struct JpegWriteMetadata
{
    const(ubyte)[] exif;
    const(ubyte)[] icc;
}

/** Encode baseline gray/RGB JPEG into a sink with explicit quality policy. */
ImageWriteResult writeJpeg(ByteSink sink, JpegWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride, ubyte quality = 75,
    Sampling sampling = Sampling.s444,
    ImageWriteOptions options = ImageWriteOptions.init,
    JpegWriteMetadata metadata = JpegWriteMetadata.init) @safe
{
    const hasMetadata = metadata.exif.length != 0 || metadata.icc.length != 0;
    if (hasMetadata && options.metadata != MetadataPolicy.allowLoss)
        return ImageWriteResult(ImageWriteError.metadataRejected);
    if (info.components != 1 && info.components != 3)
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    if (info.width == 0 || info.height == 0)
        return ImageWriteResult(ImageWriteError.invalidDimensions);
    const rowBytes = cast(size_t)info.width * info.components;
    if (rowStride < rowBytes || cast(size_t)(info.height - 1) * rowStride + rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    size_t capacity = source.length > (size_t.max - 64 * 1024) / 2
        ? size_t.max : source.length * 2 + 64 * 1024;
    if (capacity > options.maximumOutputBytes)
        capacity = options.maximumOutputBytes;
    if (capacity == 0)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto output = new ubyte[](capacity);
    auto codec = encodeJpeg(Info(info.width, info.height, info.components), source,
        rowStride, output[], EncodeOptions(quality, sampling,
            0, hasMetadata ? JpegMetadataPolicy.copy
                : JpegMetadataPolicy.reject),
        EncodeMetadata(metadata.exif, metadata.icc));
    if (codec.status == Status.destinationTooSmall)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    if (!codec.ok) return ImageWriteResult(mapWrite(codec.status));
    auto written = sink.write(output[0 .. codec.written]);
    if (written.hasError) return mapSinkFailure(written.error().bytesWritten, written.error().kind);
    if (written.value().bytesWritten != codec.written)
        return ImageWriteResult(ImageWriteError.sinkFailure, written.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none, codec.written,
        hasMetadata ? MetadataDisposition.preserved : MetadataDisposition.notApplicable);
}

/** Decode supported baseline JPEG samples into caller-owned interleaved output. */
ImageReadResult readJpeg(scope const(ubyte)[] encoded, scope ubyte[] destination,
    size_t rowStride, Limits limits = Limits.init) @safe
{
    auto codec = decodeJpeg(encoded, destination, rowStride, limits);
    return ImageReadResult(mapRead(codec.status), codec.written);
}

version (unittest)
{
    @safe unittest
    {
        import transport : MemorySink;
        import imageio.io : ImageWriteOptions, MetadataPolicy;
        ubyte[12] pixels = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255];
        auto sink = new MemorySink();
        auto written = writeJpeg(sink, JpegWriteInfo(2, 2, 3), pixels[], 6,
            75, Sampling.s444, ImageWriteOptions(MetadataPolicy.rejectLoss, 1 << 20));
        assert(written.complete && written.bytesWritten == sink.data.length);
        ubyte[12] decoded;
        auto read = readJpeg(sink.data, decoded[], 6);
        assert(read.complete && read.bytesProduced == decoded.length);
    }

    @safe unittest
    {
        import transport : MemorySink;
        ubyte[3] pixels = [1, 2, 3];
        auto sink = new MemorySink();
        auto limited = writeJpeg(sink, JpegWriteInfo(1, 1, 3), pixels[], 3,
            75, Sampling.s444, ImageWriteOptions(MetadataPolicy.rejectLoss, 1));
        assert(limited.error == ImageWriteError.outputLimitExceeded);
        auto rejected = writeJpeg(sink, JpegWriteInfo(1, 1, 3), pixels[], 3,
            75, Sampling.s444, ImageWriteOptions(MetadataPolicy.rejectLoss, 4096),
            JpegWriteMetadata([cast(ubyte)'E'], null));
        assert(rejected.error == ImageWriteError.metadataRejected);
    }
}
