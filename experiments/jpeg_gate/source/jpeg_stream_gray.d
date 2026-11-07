/// Research-only, allocation-free incremental baseline grayscale JPEG decoder.
/// Independent of the slice codec; deliberately no public format API.
module jpeg_stream_gray;

import jpeg_stream_header : PullReply, PullStatus;

enum GrayStatus : ubyte
{ ready, blocked, truncated, sourceError, invalid, unsupported, limit,
  destinationTooSmall, cancelled }

private enum Stage : ubyte
{ soi0, soi1, markerPrefix, markerCode, length0, length1, segment,
  entropy, restartPrefix, restartCode, eoiPrefix, eoiCode, afterEoi, done }
private enum Step : ubyte { value, blocked, eof, failure, invalid, limit }
private enum Phase : ubyte { dcCode, dcExtra, acCode, acExtra }

private immutable ubyte[64] zig = [
    0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
    12,19,26,33,40,48,41,34,27,20,13,6,7,14,
    21,28,35,42,49,56,57,50,43,36,29,22,15,
    23,30,37,44,51,58,59,52,45,38,31,39,46,53,
    60,61,54,47,55,62,63];

private struct Huff
{
    ubyte[16] counts;
    ubyte[256] symbols;
    ushort[16] firstCode, firstIndex;
    bool valid;
}

private bool build(ref Huff table) @safe nothrow @nogc
{
    uint code, index;
    bool[256] seen;
    foreach (size_t length; 0 .. 16)
    {
        const count = table.counts[length];
        if (index + count > 256 || code + count >= (1U << (length + 1)))
            return false;
        table.firstCode[length] = cast(ushort)code;
        table.firstIndex[length] = cast(ushort)index;
        foreach (size_t i; 0 .. count)
        {
            const symbol = table.symbols[index + i];
            if (seen[symbol]) return false;
            seen[symbol] = true;
        }
        index += count;
        code = (code + count) << 1;
    }
    table.valid = index != 0;
    return table.valid;
}

struct GrayState
{
    private Stage stage;
    private ubyte[17] window;
    private size_t windowAt, windowSize;
    private ubyte marker;
    private uint segmentSize, segmentAt;
    private ubyte[4096] segmentBytes;
    private ushort[64][4] quant;
    private bool[4] quantSeen;
    private Huff[4][2] huff;
    private ubyte componentId, quantId, dcId, acId;
    private bool frameSeen;
    private ushort restartInterval;
    private ubyte nextRestart;
    private int predictor;
    private uint width, height;
    private size_t blocksAcross, blockCount, blockIndex;
    private uint bitByte;
    private ubyte bitsLeft;
    private bool stuffedFF;
    private Phase phase;
    private uint huffCode, extraValue;
    private ubyte huffLength, extraNeeded, extraRead;
    private size_t acIndex;
    private int[64] coefficients;
    private ubyte[64] samples;
    size_t bytesPulled, bytesConsumed, pixelsWritten;
    bool cancel;

    size_t pendingCount() const @safe pure nothrow @nogc
    { return windowSize - windowAt; }
}

private Step rawByte(Source)(ref GrayState state, ref Source source,
    size_t maxBytes, out ubyte value) @safe nothrow @nogc
{
    if (state.bytesConsumed >= maxBytes) return Step.limit;
    if (state.windowAt == state.windowSize)
    {
        const reply = source.pull(state.window[]);
        if (reply.status != PullStatus.progress && reply.count != 0 ||
            reply.count > state.window.length)
            return Step.failure;
        if (reply.status == PullStatus.failure) return Step.failure;
        if (reply.status == PullStatus.eof) return Step.eof;
        if (reply.status == PullStatus.blocked || reply.count == 0)
            return Step.blocked;
        state.windowAt = 0;
        state.windowSize = reply.count;
        state.bytesPulled += reply.count;
    }
    value = state.window[state.windowAt++];
    ++state.bytesConsumed;
    return Step.value;
}

private GrayStatus map(Step step) @safe pure nothrow @nogc
{
    final switch (step)
    {
        case Step.value: return GrayStatus.ready;
        case Step.blocked: return GrayStatus.blocked;
        case Step.eof: return GrayStatus.truncated;
        case Step.failure: return GrayStatus.sourceError;
        case Step.invalid: return GrayStatus.invalid;
        case Step.limit: return GrayStatus.limit;
    }
}

private ushort word(ref const(ubyte[4096]) bytes, size_t at)
    @safe pure nothrow @nogc
{ return cast(ushort)((cast(uint)bytes[at] << 8) | bytes[at + 1]); }

private GrayStatus finishSegment(ref GrayState state, ulong maxPixels,
    size_t destinationLength, size_t rowStride) @safe nothrow @nogc
{
    const data = state.segmentBytes;
    const length = state.segmentSize;
    if (state.marker == 0xdb)
    {
        size_t at;
        while (at < length)
        {
            const spec = data[at++];
            if ((spec >> 4) != 0 || (spec & 15) >= 4)
                return GrayStatus.unsupported;
            if (length - at < 64) return GrayStatus.invalid;
            const id = spec & 15;
            foreach (size_t i; 0 .. 64)
            {
                const value = data[at++];
                if (value == 0) return GrayStatus.invalid;
                state.quant[id][zig[i]] = value;
            }
            state.quantSeen[id] = true;
        }
    }
    else if (state.marker == 0xc4)
    {
        size_t at;
        while (at < length)
        {
            if (length - at < 17) return GrayStatus.invalid;
            const spec = data[at++];
            if ((spec >> 4) >= 2 || (spec & 15) >= 4)
                return GrayStatus.unsupported;
            auto table = &state.huff[spec >> 4][spec & 15];
            *table = Huff.init;
            uint count;
            foreach (size_t i; 0 .. 16)
            { table.counts[i] = data[at++]; count += table.counts[i]; }
            if (count > 256 || count > length - at) return GrayStatus.invalid;
            foreach (size_t i; 0 .. count) table.symbols[i] = data[at++];
            if (!build(*table)) return GrayStatus.invalid;
        }
    }
    else if (state.marker == 0xc0)
    {
        if (state.frameSeen || length != 9 || data[0] != 8 ||
            data[5] != 1 || data[7] != 0x11 || data[8] >= 4)
            return GrayStatus.unsupported;
        state.height = word(data, 1);
        state.width = word(data, 3);
        if (state.width == 0 || state.height == 0 ||
            cast(ulong)state.width * state.height > maxPixels)
            return GrayStatus.limit;
        state.componentId = data[6];
        state.quantId = data[8];
        state.blocksAcross = (cast(size_t)state.width + 7) / 8;
        state.blockCount = state.blocksAcross *
            ((cast(size_t)state.height + 7) / 8);
        state.frameSeen = true;
    }
    else if (state.marker == 0xdd)
    {
        if (length != 2) return GrayStatus.invalid;
        state.restartInterval = word(data, 0);
    }
    else if (state.marker == 0xda)
    {
        if (!state.frameSeen || length != 6 || data[0] != 1 ||
            data[1] != state.componentId || data[3] != 0 ||
            data[4] != 63 || data[5] != 0)
            return GrayStatus.unsupported;
        const selector = data[2];
        state.dcId = selector >> 4;
        state.acId = selector & 15;
        if (state.dcId >= 4 || state.acId >= 4 ||
            !state.quantSeen[state.quantId] ||
            !state.huff[0][state.dcId].valid ||
            !state.huff[1][state.acId].valid)
            return GrayStatus.invalid;
        if (rowStride < state.width ||
            state.height > 1 &&
            rowStride > (size_t.max - state.width) / (state.height - 1) ||
            (cast(size_t)(state.height - 1) * rowStride + state.width) >
            destinationLength)
            return GrayStatus.destinationTooSmall;
        state.stage = Stage.entropy;
        state.phase = Phase.dcCode;
        state.acIndex = 1;
        return GrayStatus.ready;
    }
    else if (state.marker != 0xfe &&
        !(state.marker >= 0xe0 && state.marker <= 0xef))
        return GrayStatus.unsupported;
    state.stage = Stage.markerPrefix;
    return GrayStatus.ready;
}

private Step bit(Source)(ref GrayState state, ref Source source,
    size_t maxBytes, out uint value) @safe nothrow @nogc
{
    if (state.bitsLeft == 0)
    {
        ubyte byteValue;
        const result = rawByte(state, source, maxBytes, byteValue);
        if (result != Step.value) return result;
        if (state.stuffedFF)
        {
            if (byteValue != 0) return Step.invalid;
            state.stuffedFF = false;
            state.bitByte = 0xff;
        }
        else if (byteValue == 0xff)
        {
            state.stuffedFF = true;
            return bit(state, source, maxBytes, value);
        }
        else state.bitByte = byteValue;
        state.bitsLeft = 8;
    }
    value = (state.bitByte >> --state.bitsLeft) & 1;
    return Step.value;
}

private Step huffman(Source)(ref GrayState state, ref Source source,
    size_t maxBytes, ref Huff table, out int symbol) @safe nothrow @nogc
{
    while (state.huffLength < 16)
    {
        uint value;
        const result = bit(state, source, maxBytes, value);
        if (result != Step.value) return result;
        state.huffCode = (state.huffCode << 1) | value;
        const index = state.huffLength++;
        const first = table.firstCode[index];
        if (state.huffCode >= first &&
            state.huffCode - first < table.counts[index])
        {
            symbol = table.symbols[table.firstIndex[index] +
                state.huffCode - first];
            state.huffCode = 0;
            state.huffLength = 0;
            return Step.value;
        }
    }
    return Step.invalid;
}

private Step extra(Source)(ref GrayState state, ref Source source,
    size_t maxBytes, out int signedValue) @safe nothrow @nogc
{
    while (state.extraRead < state.extraNeeded)
    {
        uint value;
        const result = bit(state, source, maxBytes, value);
        if (result != Step.value) return result;
        state.extraValue = (state.extraValue << 1) | value;
        ++state.extraRead;
    }
    const raw = state.extraValue;
    const count = state.extraNeeded;
    signedValue = count == 0 ? 0 :
        raw < (1U << (count - 1)) ?
        cast(int)(raw - ((1U << count) - 1)) : cast(int)raw;
    state.extraValue = 0;
    state.extraRead = state.extraNeeded = 0;
    return Step.value;
}

private immutable double[8][8] basis = [
    [0.353553390593,0.353553390593,0.353553390593,0.353553390593,
     0.353553390593,0.353553390593,0.353553390593,0.353553390593],
    [0.490392640202,0.415734806151,0.277785116510,0.097545161008,
    -0.097545161008,-0.277785116510,-0.415734806151,-0.490392640202],
    [0.461939766256,0.191341716183,-0.191341716183,-0.461939766256,
    -0.461939766256,-0.191341716183,0.191341716183,0.461939766256],
    [0.415734806151,-0.097545161008,-0.490392640202,-0.277785116510,
     0.277785116510,0.490392640202,0.097545161008,-0.415734806151],
    [0.353553390593,-0.353553390593,-0.353553390593,0.353553390593,
     0.353553390593,-0.353553390593,-0.353553390593,0.353553390593],
    [0.277785116510,-0.490392640202,0.097545161008,0.415734806151,
    -0.415734806151,-0.097545161008,0.490392640202,-0.277785116510],
    [0.191341716183,-0.461939766256,0.461939766256,-0.191341716183,
    -0.191341716183,0.461939766256,-0.461939766256,0.191341716183],
    [0.097545161008,-0.277785116510,0.415734806151,-0.490392640202,
     0.490392640202,-0.415734806151,0.277785116510,-0.097545161008]
];

private void writeBlock(ref GrayState state, scope ubyte[] destination,
    size_t rowStride) @safe nothrow @nogc
{
    double[64] horizontal;
    foreach (size_t v; 0 .. 8)
        foreach (size_t x; 0 .. 8)
        {
            double value = 0;
            foreach (size_t u; 0 .. 8)
                value += basis[u][x] * state.coefficients[v * 8 + u];
            horizontal[v * 8 + x] = value;
        }
    foreach (size_t y; 0 .. 8)
        foreach (size_t x; 0 .. 8)
        {
            double value = 128;
            foreach (size_t v; 0 .. 8)
                value += basis[v][y] * horizontal[v * 8 + x];
            const rounded = cast(int)(value + (value >= 0 ? 0.5 : -0.5));
            state.samples[y * 8 + x] = cast(ubyte)(rounded < 0 ? 0 :
                rounded > 255 ? 255 : rounded);
        }
    const x0 = (state.blockIndex % state.blocksAcross) * 8;
    const y0 = (state.blockIndex / state.blocksAcross) * 8;
    foreach (size_t y; 0 .. 8)
        foreach (size_t x; 0 .. 8)
            if (x0 + x < state.width && y0 + y < state.height)
            {
                destination[(y0 + y) * rowStride + x0 + x] =
                    state.samples[y * 8 + x];
                ++state.pixelsWritten;
            }
    state.coefficients[] = 0;
    state.acIndex = 1;
    state.phase = Phase.dcCode;
    ++state.blockIndex;
}

private bool validPadding(ref const GrayState state) @safe pure nothrow @nogc
{
    return state.bitsLeft == 0 ||
        (state.bitByte & ((1U << state.bitsLeft) - 1)) ==
        ((1U << state.bitsLeft) - 1);
}

/// Advance with the same destination allocation and stride on every call.
/// Failed decode can leave previously completed 8x8 blocks in destination.
GrayStatus advanceGray(Source)(ref GrayState state, ref Source source,
    scope ubyte[] destination, size_t rowStride,
    size_t maxBytes = 64 * 1024 * 1024, ulong maxPixels = 64_000_000)
    @safe nothrow @nogc
{
    while (true)
    {
        if (state.cancel) return GrayStatus.cancelled;
        if (state.stage == Stage.done) return GrayStatus.ready;
        if (state.stage == Stage.entropy)
        {
            Step result;
            int value;
            final switch (state.phase)
            {
                case Phase.dcCode:
                    result = huffman(state, source, maxBytes,
                        state.huff[0][state.dcId], value);
                    if (result != Step.value) return map(result);
                    if (value > 11) return GrayStatus.invalid;
                    state.extraNeeded = cast(ubyte)value;
                    state.phase = Phase.dcExtra;
                    break;
                case Phase.dcExtra:
                    result = extra(state, source, maxBytes, value);
                    if (result != Step.value) return map(result);
                    if (state.predictor + value < -2047 ||
                        state.predictor + value > 2047)
                        return GrayStatus.invalid;
                    state.predictor += value;
                    state.coefficients[0] = state.predictor *
                        state.quant[state.quantId][0];
                    state.phase = Phase.acCode;
                    break;
                case Phase.acCode:
                    if (state.acIndex == 64)
                    {
                        writeBlock(state, destination, rowStride);
                        break;
                    }
                    result = huffman(state, source, maxBytes,
                        state.huff[1][state.acId], value);
                    if (result != Step.value) return map(result);
                    if (value == 0)
                    {
                        writeBlock(state, destination, rowStride);
                        break;
                    }
                    if ((value & 15) == 0)
                    {
                        if (value != 0xf0 || state.acIndex + 16 > 64)
                            return GrayStatus.invalid;
                        state.acIndex += 16;
                        break;
                    }
                    state.acIndex += value >> 4;
                    if (state.acIndex >= 64 || (value & 15) > 10)
                        return GrayStatus.invalid;
                    state.extraNeeded = cast(ubyte)(value & 15);
                    state.phase = Phase.acExtra;
                    break;
                case Phase.acExtra:
                    result = extra(state, source, maxBytes, value);
                    if (result != Step.value) return map(result);
                    state.coefficients[zig[state.acIndex]] = value *
                        state.quant[state.quantId][zig[state.acIndex]];
                    ++state.acIndex;
                    state.phase = Phase.acCode;
                    break;
            }
            if (state.blockIndex > 0 && state.phase == Phase.dcCode)
            {
                if (state.blockIndex == state.blockCount ||
                    state.restartInterval != 0 &&
                    state.blockIndex % state.restartInterval == 0)
                {
                    if (!validPadding(state)) return GrayStatus.invalid;
                    state.bitsLeft = 0;
                    state.stage = state.blockIndex == state.blockCount ?
                        Stage.eoiPrefix : Stage.restartPrefix;
                }
            }
            continue;
        }
        ubyte value;
        const readResult = rawByte(state, source, maxBytes, value);
        if (state.stage == Stage.afterEoi && readResult == Step.eof)
        { state.stage = Stage.done; return GrayStatus.ready; }
        if (readResult != Step.value) return map(readResult);
        final switch (state.stage)
        {
            case Stage.soi0:
                if (value != 0xff) return GrayStatus.invalid;
                state.stage = Stage.soi1; break;
            case Stage.soi1:
                if (value != 0xd8) return GrayStatus.invalid;
                state.stage = Stage.markerPrefix; break;
            case Stage.markerPrefix:
                if (value != 0xff) return GrayStatus.invalid;
                state.stage = Stage.markerCode; break;
            case Stage.markerCode:
                if (value == 0xff) break;
                if (value == 0 || value == 0xd8 || value == 0xd9 ||
                    value == 0x01 || value >= 0xd0 && value <= 0xd7)
                    return GrayStatus.invalid;
                state.marker = value;
                state.stage = Stage.length0; break;
            case Stage.length0:
                state.segmentSize = cast(uint)value << 8;
                state.stage = Stage.length1; break;
            case Stage.length1:
                state.segmentSize |= value;
                if (state.segmentSize < 2) return GrayStatus.invalid;
                state.segmentSize -= 2;
                state.segmentAt = 0;
                if ((state.marker == 0xdb || state.marker == 0xc4 ||
                    state.marker == 0xc0 || state.marker == 0xdd ||
                    state.marker == 0xda) &&
                    state.segmentSize > state.segmentBytes.length)
                    return GrayStatus.unsupported;
                state.stage = Stage.segment;
                if (state.segmentSize == 0)
                {
                    const status = finishSegment(state, maxPixels,
                        destination.length, rowStride);
                    if (status != GrayStatus.ready) return status;
                }
                break;
            case Stage.segment:
                if (state.segmentAt < state.segmentBytes.length)
                    state.segmentBytes[state.segmentAt] = value;
                ++state.segmentAt;
                if (state.segmentAt == state.segmentSize)
                {
                    const status = finishSegment(state, maxPixels,
                        destination.length, rowStride);
                    if (status != GrayStatus.ready) return status;
                }
                break;
            case Stage.restartPrefix:
                if (value != 0xff) return GrayStatus.invalid;
                state.stage = Stage.restartCode; break;
            case Stage.restartCode:
                if (value != 0xd0 + state.nextRestart)
                    return GrayStatus.invalid;
                state.nextRestart = cast(ubyte)((state.nextRestart + 1) & 7);
                state.predictor = 0;
                state.stuffedFF = false;
                state.stage = Stage.entropy; break;
            case Stage.eoiPrefix:
                if (value != 0xff) return GrayStatus.invalid;
                state.stage = Stage.eoiCode; break;
            case Stage.eoiCode:
                if (value != 0xd9) return GrayStatus.unsupported;
                state.stage = Stage.afterEoi; break;
            case Stage.afterEoi:
                return GrayStatus.unsupported;
            case Stage.entropy, Stage.done: assert(false);
        }
    }
}
