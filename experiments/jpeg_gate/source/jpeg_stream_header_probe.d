/// Resumable, fixed-window header-source regression.
module jpeg_stream_header_probe;

import jpeg_stream_header;
import jpeg_research : inspectJpegFrame, Limits;
import std.file : read;

static assert(HeaderState.sizeof <= 256);

struct ShortSource
{
    const(ubyte)[] bytes;
    size_t cursor, maxChunk, blockAt = size_t.max, failAt = size_t.max;

    PullReply pull(scope ubyte[] target) @safe pure nothrow @nogc
    {
        if (cursor >= failAt) return PullReply(PullStatus.failure);
        if (cursor >= blockAt) return PullReply(PullStatus.blocked);
        if (cursor == bytes.length) return PullReply(PullStatus.eof);
        size_t count = target.length;
        if (count > maxChunk) count = maxChunk;
        if (count > bytes.length - cursor) count = bytes.length - cursor;
        if (count > failAt - cursor) count = failAt - cursor;
        if (count > blockAt - cursor) count = blockAt - cursor;
        target[0 .. count] = bytes[cursor .. cursor + count];
        cursor += count;
        return PullReply(PullStatus.progress, count);
    }
}

struct BrokenSource
{
    PullReply reply;
    PullReply pull(scope ubyte[] target) @safe pure nothrow @nogc
    { return reply; }
}

void inspect(ubyte[] file)
{
    const oracle = inspectJpegFrame(file[]);
    assert(oracle.ok);
    size_t headerLength;
    foreach (chunk; [cast(size_t)1, 2, 17, 64])
    {
        ShortSource source = ShortSource(file[], 0, chunk);
        HeaderState state;
        assert(advanceHeader(state, source) == HeaderStatus.ready);
        assert(state.frame.info == oracle.info &&
            state.frame.signal == oracle.signal &&
            state.frame.ids == oracle.ids &&
            state.frame.horizontal == oracle.horizontal &&
            state.frame.vertical == oracle.vertical);
        assert(state.bytesConsumed < file.length);
        assert(state.bytesPulled == source.cursor &&
            state.bytesPulled >= state.bytesConsumed &&
            state.bytesPulled - state.bytesConsumed <= 16);
        ubyte[17] pending;
        assert(state.copyPending(pending[]));
        assert(pending[0 .. state.pendingCount] ==
            file[state.bytesConsumed .. state.bytesPulled]);
        auto remainder = pending[0 .. state.pendingCount].dup ~
            file[source.cursor .. $];
        assert(remainder == file[state.bytesConsumed .. $]);
        if (headerLength == 0) headerLength = state.bytesConsumed;
        else assert(headerLength == state.bytesConsumed);
        assert(advanceHeader(state, source) == HeaderStatus.ready &&
            state.bytesConsumed == headerLength);
    }
    const exhaustive = headerLength < 2000 ? headerLength : 512;
    foreach (size_t cut; 0 .. exhaustive)
    {
        ShortSource source = ShortSource(file[0 .. cut], 0, 7);
        HeaderState state;
        assert(advanceHeader(state, source) == HeaderStatus.truncated);
        assert(state.bytesConsumed == cut);
    }
    if (exhaustive < headerLength)
    {
        ShortSource source = ShortSource(file[0 .. headerLength - 1], 0, 7);
        HeaderState state;
        assert(advanceHeader(state, source) == HeaderStatus.truncated);
        assert(state.bytesConsumed == headerLength - 1);
    }
    foreach (cut; [cast(size_t)0, 2, 10, headerLength - 1])
    {
        ShortSource source = ShortSource(file[], 0, 1,
            size_t.max, cut);
        HeaderState state;
        assert(advanceHeader(state, source) == HeaderStatus.sourceError);
        assert(state.bytesConsumed == cut);
    }
    ShortSource blocked = ShortSource(file[], 0, 1, 37);
    HeaderState paused;
    assert(advanceHeader(paused, blocked) == HeaderStatus.blocked);
    const consumed = paused.bytesConsumed;
    assert(consumed == 37);
    blocked.blockAt = size_t.max;
    assert(advanceHeader(paused, blocked) == HeaderStatus.ready &&
        paused.bytesConsumed == headerLength);
    ShortSource cancelledSource = ShortSource(file[], 0, 1, 37);
    HeaderState cancelled;
    assert(advanceHeader(cancelled, cancelledSource) == HeaderStatus.blocked);
    cancelled.cancel = true;
    assert(advanceHeader(cancelled, cancelledSource) ==
        HeaderStatus.cancelled && cancelled.bytesConsumed == 37);
    ShortSource budgetSource = ShortSource(file[], 0, 17);
    HeaderState budget;
    assert(advanceHeader(budget, budgetSource, headerLength - 1) ==
        HeaderStatus.limit && budget.bytesConsumed == headerLength - 1);
    assert(advanceHeader(budget, budgetSource, headerLength) ==
        HeaderStatus.ready && budget.bytesConsumed == headerLength);
    ShortSource pixelsSource = ShortSource(file[], 0, 17);
    HeaderState pixels;
    assert(advanceHeader(pixels, pixelsSource, 1024 * 1024,
        Limits(64 * 1024 * 1024, 1)) == HeaderStatus.limit);
}

void main(string[] args)
{
    assert(args.length == 5);
    inspect(cast(ubyte[])read(args[1]));
    inspect(cast(ubyte[])read(args[2]));
    inspect(cast(ubyte[])read(args[3]));
    auto progressive = cast(ubyte[])read(args[4]);
    ShortSource source = ShortSource(progressive[], 0, 2);
    HeaderState state;
    assert(advanceHeader(state, source) == HeaderStatus.unsupported);
    ubyte[6] invalidLength = [0xff, 0xd8, 0xff, 0xe1, 0, 1];
    ShortSource shortSegment = ShortSource(invalidLength[], 0, 1);
    HeaderState malformed;
    assert(advanceHeader(malformed, shortSegment) == HeaderStatus.invalid);
    ubyte[6] hugeLength = [0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff];
    ShortSource missingPayload = ShortSource(hugeLength[], 0, 2);
    HeaderState truncated;
    assert(advanceHeader(truncated, missingPayload) ==
        HeaderStatus.truncated);
    BrokenSource excessive = BrokenSource(PullReply(PullStatus.progress, 18));
    HeaderState badReply;
    assert(advanceHeader(badReply, excessive) == HeaderStatus.sourceError);
    BrokenSource eofWithBytes = BrokenSource(PullReply(PullStatus.eof, 1));
    HeaderState badEof;
    assert(advanceHeader(badEof, eofWithBytes) == HeaderStatus.sourceError);
    auto baseline = cast(ubyte[])read(args[1]);
    ShortSource noProgress = ShortSource(baseline[], 0, 0);
    HeaderState waiting;
    assert(advanceHeader(waiting, noProgress) == HeaderStatus.blocked &&
        waiting.bytesPulled == 0 && waiting.bytesConsumed == 0);
    noProgress.maxChunk = 1;
    assert(advanceHeader(waiting, noProgress) == HeaderStatus.ready);
}
