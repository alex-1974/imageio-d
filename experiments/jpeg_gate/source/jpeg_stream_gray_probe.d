/// Short-read, backpressure and exact native-pixel streaming regression.
module jpeg_stream_gray_probe;

import jpeg_stream_gray;
import jpeg_stream_header : PullReply, PullStatus;
import jpeg_research : decodeJpegPlanes, inspectJpegFrame, MutablePlane;
import std.file : read;
import std.stdio : writeln;

static assert(GrayState.sizeof <= 12 * 1024);

struct ChunkSource
{
    const(ubyte)[] data;
    size_t cursor, available, chunk;
    size_t failAt = size_t.max;

    PullReply pull(scope ubyte[] target) @safe pure nothrow @nogc
    {
        if (cursor >= failAt) return PullReply(PullStatus.failure);
        if (cursor == data.length) return PullReply(PullStatus.eof);
        if (cursor >= available) return PullReply(PullStatus.blocked);
        size_t count = target.length;
        if (count > chunk) count = chunk;
        if (count > available - cursor) count = available - cursor;
        if (count > data.length - cursor) count = data.length - cursor;
        if (count > failAt - cursor) count = failAt - cursor;
        target[0 .. count] = data[cursor .. cursor + count];
        cursor += count;
        return PullReply(PullStatus.progress, count);
    }
}

private void inspect(ubyte[] file, size_t chunk, size_t feed)
{
    const frame = inspectJpegFrame(file[]);
    assert(frame.ok && frame.info.components == 1);
    const width = frame.info.width, height = frame.info.height;
    const stride = cast(size_t)width + 5;
    auto expected = new ubyte[stride * height + 13];
    auto actual = new ubyte[stride * height + 13];
    expected[] = 0xa5;
    actual[] = 0xa5;
    MutablePlane[1] planes = [MutablePlane(expected[], stride)];
    const reference = decodeJpegPlanes(file[], planes[]);
    assert(reference.ok);
    ChunkSource source = ChunkSource(file[], 0, feed, chunk);
    GrayState state;
    GrayStatus status;
    size_t pauses;
    while (true)
    {
        status = advanceGray(state, source, actual[], stride);
        if (status != GrayStatus.blocked) break;
        ++pauses;
        assert(source.available < file.length);
        const next = source.available + feed;
        source.available = next < file.length ? next : file.length;
    }
    assert(status == GrayStatus.ready);
    assert(state.pixelsWritten == cast(size_t)width * height);
    assert(state.bytesConsumed == file.length &&
        state.bytesPulled == file.length && source.cursor == file.length);
    if (actual != expected)
        foreach (size_t i; 0 .. actual.length)
            if (actual[i] != expected[i])
            {
                writeln("gray mismatch file=", file.length, " chunk=", chunk,
                    " feed=", feed, " index=", i, " got=", actual[i],
                    " expected=", expected[i]);
                break;
            }
    assert(actual == expected);
    if (feed < file.length) assert(pauses > 0);
    assert(advanceGray(state, source, actual[], stride) == GrayStatus.ready);
}

private void negative(ubyte[] file)
{
    const frame = inspectJpegFrame(file[]);
    assert(frame.ok && frame.info.components == 1);
    auto pixels = new ubyte[cast(size_t)frame.info.width * frame.info.height + 11];
    foreach (cut; [cast(size_t)0, 1, 2, 10, 100,
        file.length / 2, file.length - 2, file.length - 1])
    {
        if (cut >= file.length) continue;
        pixels[] = 0xa5;
        ChunkSource source = ChunkSource(file[0 .. cut], 0, cut, 2);
        GrayState state;
        const status = advanceGray(state, source, pixels[], frame.info.width);
        assert(status == GrayStatus.truncated);
        assert(state.bytesConsumed == cut &&
            pixels[$ - 1] == 0xa5);
    }
    foreach (cut; [cast(size_t)0, 2, 100, file.length - 2])
    {
        pixels[] = 0xa5;
        ChunkSource source = ChunkSource(file[], 0, file.length, 1, cut);
        GrayState state;
        assert(advanceGray(state, source, pixels[], frame.info.width) ==
            GrayStatus.sourceError);
        assert(state.bytesConsumed == cut && pixels[$ - 1] == 0xa5);
    }
    ChunkSource source = ChunkSource(file[], 0, file.length, 17);
    GrayState small;
    assert(advanceGray(small, source, pixels[], frame.info.width,
        file.length / 2) == GrayStatus.limit);
    ChunkSource narrow = ChunkSource(file[], 0, file.length, 17);
    GrayState insufficient;
    auto tiny = pixels[0 .. frame.info.width - 1];
    assert(advanceGray(insufficient, narrow, tiny, frame.info.width) ==
        GrayStatus.destinationTooSmall);
    assert(insufficient.pixelsWritten == 0);
    ChunkSource blocked = ChunkSource(file[], 0, 2, 1);
    GrayState cancelled;
    assert(advanceGray(cancelled, blocked, pixels[], frame.info.width) ==
        GrayStatus.blocked);
    cancelled.cancel = true;
    assert(advanceGray(cancelled, blocked, pixels[], frame.info.width) ==
        GrayStatus.cancelled);
    auto trailing = file.dup ~ cast(ubyte)0;
    ChunkSource extra = ChunkSource(trailing[], 0, trailing.length, 17);
    GrayState extraState;
    assert(advanceGray(extraState, extra, pixels[], frame.info.width) ==
        GrayStatus.unsupported);
}

void main(string[] args)
{
    assert(args.length == 5);
    foreach (size_t i; 1 .. 4)
    {
        auto file = cast(ubyte[])read(args[i]);
        inspect(file, 1, 31);
        inspect(file, 2, 127);
        inspect(file, 17, 257);
        negative(file);
    }
    auto progressive = cast(ubyte[])read(args[4]);
    auto pixels = new ubyte[4096];
    ChunkSource source = ChunkSource(progressive[], 0, progressive.length, 1);
    GrayState state;
    assert(advanceGray(state, source, pixels[], 64) ==
        GrayStatus.unsupported);
}
