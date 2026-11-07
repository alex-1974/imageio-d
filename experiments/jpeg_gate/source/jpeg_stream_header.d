/// Fixed-memory, pull-based JPEG header experiment; no entropy decoding.
module jpeg_stream_header;

import jpeg_research : FrameResult, Info, ComponentSignal, Limits, Status;

enum HeaderStatus : ubyte
{
    ready, blocked, truncated, sourceError, invalid, unsupported, limit,
    cancelled
}

enum PullStatus : ubyte { progress, blocked, eof, failure }
struct PullReply { PullStatus status; size_t count; }

private enum Stage : ubyte
{ soiFirst, soiSecond, markerPrefix, markerCode, lengthHigh, lengthLow,
  payload, done }

struct HeaderState
{
    private Stage stage;
    private ubyte[17] window;
    private size_t windowPosition, windowLength;
    private ubyte marker;
    private size_t markerOffset, segmentLength, remaining, prefixLength;
    private ubyte[32] prefix;
    private bool frameSeen, jfifSeen;
    private int adobeTransform = -1;
    FrameResult frame;
    size_t bytesPulled, bytesConsumed;
    bool cancel;

    /// Bytes already pulled from the source but not consumed by the parser.
    size_t pendingCount() const @safe pure nothrow @nogc
    { return windowLength - windowPosition; }

    bool copyPending(scope ubyte[] destination) const
        @safe pure nothrow @nogc
    {
        if (destination.length < pendingCount) return false;
        destination[0 .. pendingCount] = window[windowPosition .. windowLength];
        return true;
    }
}

private enum ByteStatus : ubyte { value, blocked, truncated, sourceError }

private ByteStatus nextByte(Source)(ref HeaderState state, ref Source source,
    out ubyte value) @safe nothrow @nogc
{
    if (state.windowPosition == state.windowLength)
    {
        const reply = source.pull(state.window[]);
        if (reply.status != PullStatus.progress && reply.count != 0)
            return ByteStatus.sourceError;
        if (reply.status == PullStatus.failure) return ByteStatus.sourceError;
        if (reply.status == PullStatus.eof) return ByteStatus.truncated;
        if (reply.status == PullStatus.blocked || reply.count == 0)
            return ByteStatus.blocked;
        if (reply.count > state.window.length)
            return ByteStatus.sourceError;
        state.windowPosition = 0;
        state.windowLength = reply.count;
        state.bytesPulled += reply.count;
    }
    value = state.window[state.windowPosition++];
    ++state.bytesConsumed;
    return ByteStatus.value;
}

private ushort word(ref const(ubyte[32]) bytes, size_t at)
    @safe pure nothrow @nogc
{ return cast(ushort)((cast(uint)bytes[at] << 8) | bytes[at + 1]); }

private HeaderStatus finishSegment(ref HeaderState state, Limits limits)
    @safe pure nothrow @nogc
{
    const payloadLength = state.segmentLength - 2;
    const data = state.prefix;
    if (state.marker == 0xc0)
    {
        if (state.frameSeen || payloadLength < 6 || data[0] != 8)
            return HeaderStatus.unsupported;
        const components = data[5];
        if ((components != 1 && components != 3) ||
            payloadLength != 6 + cast(size_t)components * 3)
            return HeaderStatus.unsupported;
        const height = word(data, 1), width = word(data, 3);
        if (width == 0 || height == 0 ||
            cast(ulong)width * height > limits.maxPixels)
            return HeaderStatus.limit;
        state.frame.info = Info(width, height, components);
        foreach (size_t c; 0 .. components)
        {
            state.frame.ids[c] = data[6 + 3 * c];
            foreach (size_t k; 0 .. c)
                if (state.frame.ids[k] == state.frame.ids[c])
                    return HeaderStatus.invalid;
            const sampling = data[7 + 3 * c];
            state.frame.horizontal[c] = sampling >> 4;
            state.frame.vertical[c] = sampling & 15;
            if ((state.frame.horizontal[c] != 1 &&
                 state.frame.horizontal[c] != 2) ||
                (state.frame.vertical[c] != 1 && state.frame.vertical[c] != 2))
                return HeaderStatus.unsupported;
        }
        if (components == 1)
        {
            if (state.frame.horizontal[0] != 1 ||
                state.frame.vertical[0] != 1)
                return HeaderStatus.unsupported;
        }
        else if (state.frame.horizontal[1] != 1 ||
            state.frame.vertical[1] != 1 ||
            state.frame.horizontal[2] != 1 ||
            state.frame.vertical[2] != 1 ||
            state.frame.horizontal[0] == 1 &&
            state.frame.vertical[0] == 2)
            return HeaderStatus.unsupported;
        state.frameSeen = true;
    }
    else if (state.marker == 0xe0 && state.markerOffset == 2 &&
        payloadLength >= 5 &&
        data[0 .. 5] == cast(const(ubyte)[])"JFIF\0")
        state.jfifSeen = true;
    else if (state.marker == 0xee && payloadLength >= 12 &&
        data[0 .. 5] == cast(const(ubyte)[])"Adobe")
        state.adobeTransform = data[11];
    else if (state.marker == 0xda)
    {
        if (!state.frameSeen || payloadLength !=
            1 + cast(size_t)state.frame.info.components * 2 + 3 ||
            data[0] != state.frame.info.components)
            return HeaderStatus.unsupported;
        foreach (size_t c; 0 .. state.frame.info.components)
            if (data[1 + c * 2] != state.frame.ids[c])
                return HeaderStatus.unsupported;
        if (data[payloadLength - 3] != 0 ||
            data[payloadLength - 2] != 63 ||
            data[payloadLength - 1] != 0)
            return HeaderStatus.unsupported;
        state.frame.signal = state.frame.info.components == 1 ?
            ComponentSignal.gray :
            state.adobeTransform == 0 ? ComponentSignal.adobeRGB :
            state.adobeTransform == 1 ? ComponentSignal.adobeYCbCr :
            state.adobeTransform >= 0 ? ComponentSignal.unknown :
            state.jfifSeen ? ComponentSignal.jfifYCbCr :
                ComponentSignal.unknown;
        state.frame.status = Status.ok;
        state.stage = Stage.done;
        return HeaderStatus.ready;
    }
    else if (state.marker != 0xdb && state.marker != 0xc4 &&
        state.marker != 0xdd && state.marker != 0xe1 &&
        state.marker != 0xe2 && !(state.marker >= 0xe0 &&
        state.marker <= 0xef) && state.marker != 0xfe)
        return HeaderStatus.unsupported;
    state.stage = Stage.markerPrefix;
    return HeaderStatus.blocked; // Internal continue sentinel; not returned.
}

/// Resumable scan through SOS. Source may short-read or return backpressure.
/// On ready, copied pending bytes plus subsequent source bytes begin at SOS
/// entropy start; the caller must consume pending bytes first.
/// At most 17 bytes are prefetched beyond the consumed header.
HeaderStatus advanceHeader(Source)(ref HeaderState state, ref Source source,
    size_t maxHeaderBytes = 1024 * 1024, Limits limits = Limits.init)
    @safe nothrow @nogc
{
    while (true)
    {
        if (state.cancel) return HeaderStatus.cancelled;
        if (state.stage == Stage.done) return HeaderStatus.ready;
        if (state.bytesConsumed >= maxHeaderBytes) return HeaderStatus.limit;
        ubyte value;
        const got = nextByte(state, source, value);
        if (got == ByteStatus.blocked) return HeaderStatus.blocked;
        if (got == ByteStatus.truncated) return HeaderStatus.truncated;
        if (got == ByteStatus.sourceError) return HeaderStatus.sourceError;
        final switch (state.stage)
        {
            case Stage.soiFirst:
                if (value != 0xff) return HeaderStatus.invalid;
                state.stage = Stage.soiSecond;
                break;
            case Stage.soiSecond:
                if (value != 0xd8) return HeaderStatus.invalid;
                state.stage = Stage.markerPrefix;
                break;
            case Stage.markerPrefix:
                if (value != 0xff) return HeaderStatus.invalid;
                state.markerOffset = state.bytesConsumed - 1;
                state.stage = Stage.markerCode;
                break;
            case Stage.markerCode:
                if (value == 0xff) break;
                if (value == 0 || value == 0xd9 || value == 0x01 ||
                    value >= 0xd0 && value <= 0xd7 || value == 0xd8)
                    return HeaderStatus.invalid;
                state.marker = value;
                state.stage = Stage.lengthHigh;
                break;
            case Stage.lengthHigh:
                state.segmentLength = cast(size_t)value << 8;
                state.stage = Stage.lengthLow;
                break;
            case Stage.lengthLow:
                state.segmentLength |= value;
                if (state.segmentLength < 2) return HeaderStatus.invalid;
                state.remaining = state.segmentLength - 2;
                state.prefixLength = 0;
                state.stage = Stage.payload;
                if (state.remaining == 0)
                {
                    const status = finishSegment(state, limits);
                    if (status != HeaderStatus.blocked) return status;
                }
                break;
            case Stage.payload:
                if (state.prefixLength < state.prefix.length)
                    state.prefix[state.prefixLength++] = value;
                --state.remaining;
                if (state.remaining == 0)
                {
                    const status = finishSegment(state, limits);
                    if (status != HeaderStatus.blocked) return status;
                }
                break;
            case Stage.done: assert(false);
        }
    }
}
