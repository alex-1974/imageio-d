/// Linux-only non-seekable source and pending-byte hand-off probe.
module jpeg_stream_pipe_probe;

import jpeg_stream_header;
import jpeg_research : inspectJpegFrame;
import core.stdc.errno : errno, EAGAIN, EINTR, EWOULDBLOCK;
import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;
import core.sys.posix.unistd : pipe, read, write, close;
import std.file : readFile = read;
import std.stdio : writeln;

struct PipeSource
{
    int descriptor;

    PullReply pull(scope ubyte[] destination) @trusted nothrow @nogc
    {
        // The kernel writes no more than destination.length bytes to its
        // live, caller-owned storage; the slice cannot escape this call.
        const count = read(descriptor, destination.ptr, destination.length);
        if (count > 0) return PullReply(PullStatus.progress, count);
        if (count == 0) return PullReply(PullStatus.eof);
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
            return PullReply(PullStatus.blocked);
        return PullReply(PullStatus.failure);
    }
}

private void sendBytes(int descriptor, scope const(ubyte)[] bytes)
{
    size_t offset;
    while (offset < bytes.length)
    {
        const count = write(descriptor, bytes.ptr + offset,
            bytes.length - offset);
        assert(count > 0);
        offset += count;
    }
}

private void drain(ref PipeSource source, ref ubyte[] result)
{
    ubyte[37] window;
    while (true)
    {
        const reply = source.pull(window[]);
        if (reply.status == PullStatus.blocked ||
            reply.status == PullStatus.eof) return;
        assert(reply.status == PullStatus.progress &&
            reply.count <= window.length);
        result ~= window[0 .. reply.count];
    }
}

private void inspectPipe(scope const(ubyte)[] encoded)
{
    int[2] descriptors;
    assert(pipe(descriptors) == 0);
    scope(exit)
    {
        if (descriptors[0] >= 0) close(descriptors[0]);
        if (descriptors[1] >= 0) close(descriptors[1]);
    }
    const flags = fcntl(descriptors[0], F_GETFL);
    assert(flags >= 0 &&
        fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) == 0);
    PipeSource source = PipeSource(descriptors[0]);
    HeaderState state;
    assert(advanceHeader(state, source) == HeaderStatus.blocked);
    size_t fed, pauses = 1;
    HeaderStatus status = HeaderStatus.blocked;
    while (fed < encoded.length && status == HeaderStatus.blocked)
    {
        const window = fed == 0 ? 1 : fed == 1 ? 7 : 512;
        const count = encoded.length - fed < window ?
            encoded.length - fed : window;
        sendBytes(descriptors[1], encoded[fed .. fed + count]);
        fed += count;
        status = advanceHeader(state, source);
        if (status == HeaderStatus.blocked) ++pauses;
    }
    assert(status == HeaderStatus.ready && pauses >= 2);
    const oracle = inspectJpegFrame(encoded);
    assert(oracle.ok && state.frame.info == oracle.info &&
        state.frame.signal == oracle.signal &&
        state.bytesConsumed <= state.bytesPulled &&
        state.bytesPulled <= fed);

    ubyte[17] pending;
    assert(state.copyPending(pending[]));
    ubyte[] suffix = pending[0 .. state.pendingCount].dup;
    drain(source, suffix);
    while (fed < encoded.length)
    {
        const count = encoded.length - fed < 512 ?
            encoded.length - fed : 512;
        sendBytes(descriptors[1], encoded[fed .. fed + count]);
        fed += count;
        drain(source, suffix);
    }
    close(descriptors[1]);
    descriptors[1] = -1;
    ubyte[1] tail;
    assert(source.pull(tail[]) == PullReply(PullStatus.eof));
    assert(suffix == encoded[state.bytesConsumed .. $]);
    assert(state.bytesPulled - state.bytesConsumed == state.pendingCount);
    writeln("linux pipe header bytes=", state.bytesConsumed,
        " source bytes=", encoded.length, " pauses=", pauses,
        " pending=", state.pendingCount);
}

private void inspectEarlyEof(scope const(ubyte)[] encoded)
{
    int[2] descriptors;
    assert(pipe(descriptors) == 0);
    scope(exit) close(descriptors[0]);
    sendBytes(descriptors[1], encoded[0 .. 7]);
    close(descriptors[1]);
    PipeSource source = PipeSource(descriptors[0]);
    HeaderState state;
    assert(advanceHeader(state, source) == HeaderStatus.truncated &&
        state.bytesConsumed == 7);
    PipeSource broken = PipeSource(-1);
    HeaderState failed;
    assert(advanceHeader(failed, broken) == HeaderStatus.sourceError);
}

void main(string[] args)
{
    assert(args.length == 3);
    auto baseline = cast(ubyte[])readFile(args[1]);
    auto largeIcc = cast(ubyte[])readFile(args[2]);
    inspectPipe(baseline);
    inspectPipe(largeIcc);
    inspectEarlyEof(baseline);
}
