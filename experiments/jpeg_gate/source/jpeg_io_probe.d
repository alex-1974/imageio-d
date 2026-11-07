/// Bounded prebuffered source/sink contract probe, not a streaming JPEG codec.
module jpeg_io_probe;

import std.file : read, write;
import jpeg_research;

enum IoState : ubyte { progress, eof, blocked, failure }
struct IoReply { IoState state; size_t count; }
enum TransferState : ubyte
{ complete, sourceTruncated, sourceError, sinkError, blocked, cancelled }

struct Transfer
{
    ubyte[17] window;
    size_t pending, consumed, accepted, expectedBytes;
    bool cancelled;
}

/// Each call is resumable after backpressure. Zero acceptance never spins.
/// `expectedBytes` is an outer framing contract, not JPEG self-validation.
TransferState pump(Source, Sink)(ref Transfer transfer,
    ref Source source, ref Sink sink) @safe nothrow @nogc
{
    while (true)
    {
        if (transfer.cancelled) return TransferState.cancelled;
        if (transfer.consumed == transfer.pending)
        {
            const reply = source.pull(transfer.window[]);
            if (reply.state == IoState.failure) return TransferState.sourceError;
            if (reply.state == IoState.blocked ||
                reply.state == IoState.progress && reply.count == 0)
                return TransferState.blocked;
            if (reply.state == IoState.eof)
                return transfer.accepted == transfer.expectedBytes ?
                    TransferState.complete : TransferState.sourceTruncated;
            if (reply.count > transfer.window.length)
                return TransferState.sourceError;
            transfer.pending = reply.count;
            transfer.consumed = 0;
        }
        const reply = sink.push(transfer.window[
            transfer.consumed .. transfer.pending]);
        if (reply.count > transfer.pending - transfer.consumed)
            return TransferState.sinkError;
        transfer.consumed += reply.count;
        transfer.accepted += reply.count;
        if (reply.state == IoState.failure) return TransferState.sinkError;
        if (reply.state == IoState.blocked || reply.count == 0)
            return TransferState.blocked;
    }
}

struct SliceSource
{
    const(ubyte)[] bytes;
    size_t cursor, maxChunk, failAt;
    IoReply pull(scope ubyte[] target) @safe nothrow @nogc
    {
        if (cursor >= failAt) return IoReply(IoState.failure);
        if (cursor == bytes.length) return IoReply(IoState.eof);
        size_t count = target.length;
        if (count > maxChunk) count = maxChunk;
        if (count > bytes.length - cursor) count = bytes.length - cursor;
        if (count > failAt - cursor) count = failAt - cursor;
        target[0 .. count] = bytes[cursor .. cursor + count];
        cursor += count;
        return IoReply(IoState.progress, count);
    }
}

struct SliceSink
{
    ubyte[] bytes;
    size_t cursor, maxChunk, failAt, blockAt;
    IoReply push(scope const(ubyte)[] source) @safe nothrow @nogc
    {
        if (cursor >= failAt) return IoReply(IoState.failure);
        if (cursor >= blockAt) return IoReply(IoState.blocked);
        size_t count = source.length;
        if (count > maxChunk) count = maxChunk;
        if (count > bytes.length - cursor) count = bytes.length - cursor;
        if (count > failAt - cursor) count = failAt - cursor;
        if (count > blockAt - cursor) count = blockAt - cursor;
        if (count == 0) return IoReply(IoState.failure);
        bytes[cursor .. cursor + count] = source[0 .. count];
        cursor += count;
        return IoReply(IoState.progress, count);
    }
}

void main(string[] args)
{
    assert(args.length == 3);
    auto jpeg = cast(ubyte[])read(args[1]);
    assert(jpeg.length > 32);
    auto target = new ubyte[jpeg.length + 16];
    target[] = 0xa5;
    auto source = SliceSource(jpeg[], 0, 1, size_t.max);
    auto sink = SliceSink(target[0 .. jpeg.length], 0, 1,
        size_t.max, 7);
    Transfer transfer;
    transfer.expectedBytes = jpeg.length;
    assert(pump(transfer, source, sink) == TransferState.blocked);
    assert(transfer.accepted == 7);
    sink.blockAt = size_t.max;
    assert(pump(transfer, source, sink) == TransferState.complete);
    assert(transfer.accepted == jpeg.length &&
        target[0 .. jpeg.length] == jpeg[]);
    foreach (b; target[jpeg.length .. $]) assert(b == 0xa5);
    auto failedSource = SliceSource(jpeg[], 0, 3, 12);
    auto failedSink = SliceSink(target[0 .. jpeg.length], 0, 4,
        size_t.max, size_t.max);
    Transfer sourceTransfer;
    sourceTransfer.expectedBytes = jpeg.length;
    assert(pump(sourceTransfer, failedSource, failedSink) ==
        TransferState.sourceError);
    assert(sourceTransfer.accepted == 12);
    auto shortSource = SliceSource(jpeg[0 .. $ - 2], 0, 5, size_t.max);
    failedSink.cursor = 0;
    Transfer shortTransfer;
    shortTransfer.expectedBytes = jpeg.length;
    assert(pump(shortTransfer, shortSource, failedSink) ==
        TransferState.sourceTruncated);
    assert(shortTransfer.accepted == jpeg.length - 2);
    auto normalSource = SliceSource(jpeg[], 0, 17, size_t.max);
    auto failedOutput = SliceSink(target[0 .. jpeg.length], 0, 4,
        11, size_t.max);
    Transfer sinkTransfer;
    sinkTransfer.expectedBytes = jpeg.length;
    assert(pump(sinkTransfer, normalSource, failedOutput) ==
        TransferState.sinkError);
    assert(sinkTransfer.accepted == 11);
    write(args[2], target[0 .. sinkTransfer.accepted]);
    sinkTransfer.cancelled = true;
    assert(pump(sinkTransfer, normalSource, failedOutput) ==
        TransferState.cancelled && sinkTransfer.accepted == 11);
    foreach (cut; [cast(size_t)2, jpeg.length - 2, jpeg.length - 1])
    {
        target[] = 0xa5;
        auto boundedSource = SliceSource(jpeg[], 0, 17, size_t.max);
        auto boundedSink = SliceSink(target[0 .. jpeg.length], 0, 7,
            cut, size_t.max);
        Transfer boundary;
        boundary.expectedBytes = jpeg.length;
        assert(pump(boundary, boundedSource, boundedSink) ==
            TransferState.sinkError);
        assert(boundary.accepted == cut && target[0 .. cut] == jpeg[0 .. cut]);
        foreach (b; target[cut .. $]) assert(b == 0xa5);
    }
}
