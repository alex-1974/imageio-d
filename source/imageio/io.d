/**
 * Format-neutral image-I/O source, sink and write-result contracts.
 *
 * Format modules own encoded representation and metadata policy. Transport
 * owns byte movement; this module records the image boundary outcome without
 * hiding short writes or metadata loss.
 */
module imageio.io;

import transport : ByteSink, WriteError;

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
