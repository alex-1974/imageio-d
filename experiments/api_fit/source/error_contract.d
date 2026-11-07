module error_contract;

enum ReadError
{
    none,
    sourceUnavailable,
    truncatedInput,
    invalidMetadata,
    unsupportedValues,
    insufficientWorkspace,
    invalidBuffer,
    codecFailure
}

enum WriteState { notStarted, complete, partial }

enum WriteError
{
    none,
    invalidOptions,
    unsupportedValues,
    insufficientOutput,
    metadataNotRepresentable,
    sinkFailure
}

struct ReadResult
{
    ReadError error;
    bool complete;
    size_t bytesRead;
}

struct WriteResult
{
    WriteError error;
    WriteState state;
    size_t bytesWritten;
    bool metadataLoss;
}

struct MetadataDecision
{
    bool loss;
    bool explicitlyAllowed;
}

@safe @nogc nothrow
void main()
{
    auto failedRead = ReadResult(ReadError.truncatedInput, false, 128);
    assert(!failedRead.complete && failedRead.error == ReadError.truncatedInput);

    auto partialWrite = WriteResult(WriteError.sinkFailure,
        WriteState.partial, 512, false);
    assert(partialWrite.state == WriteState.partial);
    assert(partialWrite.bytesWritten == 512);

    auto allowedLoss = MetadataDecision(true, true);
    assert(allowedLoss.loss && allowedLoss.explicitlyAllowed);
}
