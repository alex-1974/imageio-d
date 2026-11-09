/**
 * Format-neutral image-I/O source, sink and write-result contracts.
 *
 * Format modules own encoded representation and metadata policy. Transport
 * owns byte movement; this module records the image boundary outcome without
 * hiding short writes or metadata loss.
 */
module imageio.io;

import std.file : exists, remove, rename;
import std.path : buildPath, dirName, baseName;
import std.process : thisProcessID;
import std.conv : to;
import transport : ByteSink, WriteError;
import transport : FileSink;

/** Why a writer did not produce a complete encoded resource. */
enum ImageWriteError : ubyte
{
    none,
    unsupportedFormat,
    unsupportedRepresentation,
    invalidDimensions,
    metadataRejected,
    sourceFailure,
    sinkFailure,
    truncatedInput,
    outputLimitExceeded
}

/** Formats available through the bounded format-neutral writer entry point. */
enum ImageWriteFormat : ubyte { tiff }

/** Native interleaved input shared by the first format-neutral writer slice. */
struct ImageWriteRequest
{
    ImageWriteFormat format;
    uint width;
    uint height;
    ubyte channels;
    ubyte sampleBytes;
    uint rowsPerStrip;
    const(ubyte)[] source;
    size_t rowStride;
}

enum ImageReadError : ubyte
{
    none,
    unsupportedFormat,
    malformedInput,
    truncatedInput,
    checksumFailure,
    unsupportedRepresentation,
    sizeLimit,
    sourceFailure,
    codecFailure
}

struct ImageReadResult
{
    ImageReadError error = ImageReadError.none;
    size_t bytesProduced;
    @property bool complete() const @safe pure nothrow @nogc
    { return error == ImageReadError.none; }
}

/** Explicit policy for metadata that cannot be represented by the target. */
enum MetadataPolicy : ubyte
{
    rejectLoss,
    allowLoss
}

/** How the writer handled source metadata. */
enum MetadataDisposition : ubyte
{
    notApplicable,
    preserved,
    partiallyPreserved,
    discarded
}

/** Outcome of an encoding attempt, including a possible partial sink write. */
struct ImageWriteResult
{
    ImageWriteError error = ImageWriteError.none;
    size_t bytesWritten;
    MetadataDisposition metadata = MetadataDisposition.notApplicable;

    @property bool complete() const @safe pure nothrow @nogc
    {
        return error == ImageWriteError.none;
    }
}

/** Options shared by format-specific encoders. */
struct ImageWriteOptions
{
    MetadataPolicy metadata = MetadataPolicy.rejectLoss;
    size_t maximumOutputBytes = size_t.max;
}

/**
 * Run an already validated encoder against a same-directory temporary file and
 * publish it only after the encoder and close both succeed.  The encoder must
 * not retain the sink after returning.
 */
ImageWriteResult writeAtomically(string path,
    scope ImageWriteResult delegate(ByteSink sink) @safe encoder)
@safe
{
    if (path.length == 0 || encoder is null)
        return ImageWriteResult(ImageWriteError.invalidDimensions);

    auto directory = dirName(path);
    auto temporary = buildPath(directory, "." ~ baseName(path)
        ~ ".imageio-" ~ thisProcessID.to!string ~ ".tmp");
    try
    {
        if (exists(temporary)) remove(temporary);
        auto sink = new FileSink(temporary);
        auto result = encoder(sink);
        sink.close();
        if (!result.complete)
        {
            if (exists(temporary)) remove(temporary);
            return result;
        }
        rename(temporary, path);
        return result;
    }
    catch (Exception)
    {
        try if (exists(temporary)) remove(temporary);
        catch (Exception) { }
        return ImageWriteResult(ImageWriteError.sinkFailure);
    }
}

/** Map a transport sink failure without hiding the bytes already accepted. */
ImageWriteResult mapSinkFailure(size_t bytesWritten, WriteError error)
@safe pure nothrow @nogc
{
    return ImageWriteResult(ImageWriteError.sinkFailure, bytesWritten,
        MetadataDisposition.notApplicable);
}

static assert(ImageWriteResult.init.complete);

version (unittest)
{
    @safe unittest
    {
        auto result = mapSinkFailure(7, WriteError.destinationFailure);
        assert(!result.complete);
        assert(result.error == ImageWriteError.sinkFailure);
        assert(result.bytesWritten == 7);
    }
}
