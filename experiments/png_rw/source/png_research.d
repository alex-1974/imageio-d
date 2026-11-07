/// Bounded Pure-D PNG read/write experiment; deliberately not a public API.
module png_research;

import compression.checksum : crc32, Adler32, adler32;
import compression.core : DecodeStatus, DecodeLimits, ErrorCode,
    CodecResult = Result;
import compression.deflate : InflateWorkspace;
import compression.encode : encodeZlibStored, zlibStoredSize,
    RawStoredEncoderState, encodeRawStoredChunk, rawStoredSize,
    HashChainMatchFinder, encodeRawFixedLzHashChain;
import compression.zlib : inflateZlib, ZlibState, decodeZlib;

enum Status : ubyte
{
    invalidInput, ok, truncated, badCrc, invalidChunkOrder, unsupported,
    sizeLimit, workspaceTooSmall, destinationTooSmall, codecError,
    decodedSizeMismatch, invalidFilter, metadataWouldBeLost
}

enum MetadataPolicy : ubyte { rejectLoss, drop }
enum FilterStrategy : ubyte { none, adaptive }

/// Experimental zlib framing for compression-d's raw hash-chain encoder.
/// The finder is caller-owned and reset for each independent PNG stream.
private CodecResult encodeZlibHashChain(ref HashChainMatchFinder finder,
    scope const(ubyte)[] input, scope ubyte[] output)
    @safe pure nothrow @nogc
{
    if (output.length < 8) return CodecResult.needOutput;
    finder.reset();
    output[0] = 0x78;
    output[1] = 0x01;
    auto raw = encodeRawFixedLzHashChain(finder, input, output[2 .. $ - 4]);
    if (raw.status != DecodeStatus.done) return raw;
    const sum = adler32(input);
    const p = 2 + raw.produced;
    output[p] = cast(ubyte)(sum >> 24);
    output[p + 1] = cast(ubyte)(sum >> 16);
    output[p + 2] = cast(ubyte)(sum >> 8);
    output[p + 3] = cast(ubyte)sum;
    return CodecResult.done(input.length, p + 4);
}

/// Pixel edits may invalidate colour/transparency declarations. The caller
/// must explicitly attest that those declarations still describe the pixels.
struct MetadataTransfer
{
    bool colorMetadataStillApplies;
    bool dropUnsupported;
}

struct Limits
{
    ulong maxPixels = 64_000_000;
    size_t maxDecodedBytes = 256 * 1024 * 1024;
    size_t maxCompressedBytes = 256 * 1024 * 1024;
    size_t maxFileBytes = 512 * 1024 * 1024;
    size_t maxAncillaryBytes = 16 * 1024 * 1024;
}

struct Info
{
    uint width, height;
    ubyte bitDepth, colorType, channels;
    size_t rowBytes, filteredBytes, compressedBytes, ancillaryBytes;
    uint paletteEntries, transparencyBytes;
    bool hasAncillary, hasTransparency;
}

struct InspectResult
{
    Status status;
    Info info;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

struct Result
{
    Status status;
    size_t written;
    ErrorCode codec = ErrorCode.none;
    bool metadataDropped;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

struct WriteRequirements
{
    Status status;
    size_t rowBytes, filteredBytes, zlibCapacity, pngCapacity;
}

private immutable ubyte[8] signature = [137, 80, 78, 71, 13, 10, 26, 10];

private uint be32(scope const(ubyte)[] bytes, size_t p) @safe pure nothrow @nogc
{
    return (cast(uint)bytes[p] << 24) | (cast(uint)bytes[p + 1] << 16) |
        (cast(uint)bytes[p + 2] << 8) | bytes[p + 3];
}

private void put32(scope ubyte[] bytes, size_t p, uint value) @safe pure nothrow @nogc
{
    bytes[p] = cast(ubyte)(value >> 24);
    bytes[p + 1] = cast(ubyte)(value >> 16);
    bytes[p + 2] = cast(ubyte)(value >> 8);
    bytes[p + 3] = cast(ubyte)value;
}

private ubyte channelsFor(ubyte colorType) @safe pure nothrow @nogc
{
    switch (colorType)
    {
        case 0: return 1;
        case 3: return 1;
        case 2: return 3;
        case 4: return 2;
        case 6: return 4;
        default: return 0;
    }
}

private WriteRequirements readShapeRequirements(uint width, uint height,
    ubyte bitDepth, ubyte colorType, Limits limits) @safe pure nothrow @nogc
{
    const channels = channelsFor(colorType);
    bool validDepth;
    switch (colorType)
    {
        case 0: validDepth = bitDepth == 1 || bitDepth == 2 || bitDepth == 4 ||
            bitDepth == 8 || bitDepth == 16; break;
        case 3: validDepth = bitDepth == 1 || bitDepth == 2 || bitDepth == 4 ||
            bitDepth == 8; break;
        default: validDepth = bitDepth == 8 || bitDepth == 16;
    }
    if (!width || !height || !channels || !validDepth)
        return WriteRequirements(Status.unsupported);
    if (cast(ulong)width * height > limits.maxPixels)
        return WriteRequirements(Status.sizeLimit);
    const bits = cast(size_t)channels * bitDepth;
    if (width > (size_t.max - 7) / bits) return WriteRequirements(Status.sizeLimit);
    const rowBytes = (cast(size_t)width * bits + 7) / 8;
    if (rowBytes == size_t.max || height > limits.maxDecodedBytes / (rowBytes + 1))
        return WriteRequirements(Status.sizeLimit);
    return WriteRequirements(Status.ok, rowBytes, cast(size_t)height * (rowBytes + 1));
}

private WriteRequirements shapeRequirements(uint width, uint height, ubyte bitDepth,
    ubyte colorType, Limits limits = Limits.init) @safe pure nothrow @nogc
{
    const channels = channelsFor(colorType);
    if (!width || !height || colorType == 3 || !channels ||
        (bitDepth != 8 && bitDepth != 16))
        return WriteRequirements(Status.unsupported);
    if (cast(ulong)width * height > limits.maxPixels)
        return WriteRequirements(Status.sizeLimit);
    const pixelBytes = cast(size_t)channels * (bitDepth / 8);
    if (width > size_t.max / pixelBytes) return WriteRequirements(Status.sizeLimit);
    const rowBytes = cast(size_t)width * pixelBytes;
    if (rowBytes == size_t.max || height > limits.maxDecodedBytes / (rowBytes + 1))
        return WriteRequirements(Status.sizeLimit);
    const filteredBytes = cast(size_t)height * (rowBytes + 1);
    return WriteRequirements(Status.ok, rowBytes, filteredBytes);
}

WriteRequirements writeRequirements(uint width, uint height, ubyte bitDepth,
    ubyte colorType, Limits limits = Limits.init) @safe pure nothrow @nogc
{
    const shape = shapeRequirements(width, height, bitDepth, colorType, limits);
    if (shape.status != Status.ok) return shape;
    const rowBytes = shape.rowBytes, filteredBytes = shape.filteredBytes;
    // A fixed-Huffman literal can cost at most nine bits. Keep capacity above
    // both that bound and compression-d's stored-block preflight bound.
    if (filteredBytes > (size_t.max - 64) / 2) return WriteRequirements(Status.sizeLimit);
    const fixedBound = filteredBytes + (filteredBytes + 7) / 8 + 16;
    const storedBound = zlibStoredSize(filteredBytes);
    const zlibCapacity = fixedBound > storedBound ? fixedBound : storedBound;
    if (zlibCapacity > limits.maxCompressedBytes || zlibCapacity > 0x7fff_ffffU ||
        zlibCapacity > size_t.max - 57 || zlibCapacity + 57 > limits.maxFileBytes)
        return WriteRequirements(Status.sizeLimit);
    return WriteRequirements(Status.ok, rowBytes, filteredBytes,
        zlibCapacity, zlibCapacity + 57);
}

/// Fast, row-bounded stored-block variant. Output still belongs to the caller.
WriteRequirements storedRowRequirements(uint width, uint height, ubyte bitDepth,
    ubyte colorType, Limits limits = Limits.init) @safe pure nothrow @nogc
{
    const shape = shapeRequirements(width, height, bitDepth, colorType, limits);
    if (shape.status != Status.ok) return shape;
    const row = shape.rowBytes + 1;
    const storedRow = rawStoredSize(row);
    if (height > (size_t.max - 63) / storedRow)
        return WriteRequirements(Status.sizeLimit);
    const compressed = 6 + cast(size_t)height * storedRow;
    if (compressed > limits.maxCompressedBytes || compressed > 0x7fff_ffffU ||
        compressed > size_t.max - 57 || compressed + 57 > limits.maxFileBytes)
        return WriteRequirements(Status.sizeLimit);
    return WriteRequirements(Status.ok, shape.rowBytes, row, compressed,
        compressed + 57);
}

InspectResult inspectPng(scope const(ubyte)[] file, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    if (file.length < 8) return InspectResult(Status.truncated);
    if (file.length > limits.maxFileBytes) return InspectResult(Status.sizeLimit);
    if (file[0 .. 8] != signature[]) return InspectResult(Status.invalidInput);
    size_t p = 8;
    bool seenHeader, seenData, dataEnded, seenPalette, seenTransparency;
    Info info;
    while (p < file.length)
    {
        if (file.length - p < 12) return InspectResult(Status.truncated);
        const length = cast(size_t)be32(file, p);
        if (length > 0x7fff_ffffU) return InspectResult(Status.invalidInput);
        if (length > file.length - p - 12) return InspectResult(Status.truncated);
        const type = file[p + 4 .. p + 8];
        foreach (letter; type)
            if (!((letter >= 'A' && letter <= 'Z') ||
                  (letter >= 'a' && letter <= 'z')))
                return InspectResult(Status.invalidInput);
        if ((type[2] & 32) != 0) return InspectResult(Status.invalidInput);
        const data = file[p + 8 .. p + 8 + length];
        if (crc32(file[p + 4 .. p + 8 + length]) != be32(file, p + 8 + length))
            return InspectResult(Status.badCrc);
        if (!seenHeader && type != "IHDR") return InspectResult(Status.invalidChunkOrder);
        if (type == "IHDR")
        {
            if (seenHeader || length != 13) return InspectResult(Status.invalidChunkOrder);
            info.width = be32(data, 0); info.height = be32(data, 4);
            info.bitDepth = data[8]; info.colorType = data[9];
            info.channels = channelsFor(info.colorType);
            if (data[10] != 0 || data[11] != 0 || data[12] != 0)
                return InspectResult(Status.unsupported);
            auto req = readShapeRequirements(info.width, info.height, info.bitDepth,
                info.colorType, limits);
            if (req.status != Status.ok) return InspectResult(req.status);
            info.rowBytes = req.rowBytes; info.filteredBytes = req.filteredBytes;
            seenHeader = true;
        }
        else if (type == "IDAT")
        {
            if (dataEnded) return InspectResult(Status.invalidChunkOrder);
            if (info.colorType == 3 && !seenPalette)
                return InspectResult(Status.invalidChunkOrder);
            if (length > limits.maxCompressedBytes - info.compressedBytes)
                return InspectResult(Status.sizeLimit);
            info.compressedBytes += length;
            seenData = true;
        }
        else if (type == "IEND")
        {
            if (!seenData || length != 0 || p + 12 != file.length)
                return InspectResult(Status.invalidChunkOrder);
            if (!info.compressedBytes) return InspectResult(Status.invalidInput);
            return InspectResult(Status.ok, info);
        }
        else if (type == "PLTE")
        {
            if (seenData || seenPalette || seenTransparency ||
                info.colorType == 0 || info.colorType == 4 ||
                length == 0 || length > 768 || length % 3 != 0)
                return InspectResult(Status.invalidChunkOrder);
            const entries = cast(uint)(length / 3);
            if (info.colorType == 3 && entries > (1U << info.bitDepth))
                return InspectResult(Status.invalidInput);
            info.paletteEntries = entries;
            info.hasAncillary = true; // Optional truecolour palette would be lost on write.
            seenPalette = true;
        }
        else if (type == "tRNS")
        {
            if (seenData || seenTransparency || info.colorType == 4 || info.colorType == 6)
                return InspectResult(Status.invalidChunkOrder);
            const expected = info.colorType == 0 ? 2U : info.colorType == 2 ? 6U : 0U;
            if (info.colorType == 3 ?
                (!seenPalette || length == 0 || length > info.paletteEntries) :
                length != expected)
                return InspectResult(Status.invalidInput);
            if (info.colorType == 0 &&
                ((cast(uint)data[0] << 8) | data[1]) >= (1U << info.bitDepth))
                return InspectResult(Status.invalidInput);
            if (info.colorType == 2 && info.bitDepth == 8 &&
                (data[0] != 0 || data[2] != 0 || data[4] != 0))
                return InspectResult(Status.invalidInput);
            if (length > limits.maxAncillaryBytes - info.ancillaryBytes)
                return InspectResult(Status.sizeLimit);
            info.ancillaryBytes += length;
            info.transparencyBytes = cast(uint)length;
            info.hasTransparency = true;
            info.hasAncillary = true;
            seenTransparency = true;
        }
        else
        {
            if (seenData) dataEnded = true;
            // Treat animation as a separate capability, never as an ordinary
            // still image with silently discarded frame/timing information.
            if (type == "acTL" || type == "fcTL" || type == "fdAT")
                return InspectResult(Status.unsupported);
            if ((type[0] & 32) == 0) return InspectResult(Status.unsupported);
            if (length > limits.maxAncillaryBytes - info.ancillaryBytes)
                return InspectResult(Status.sizeLimit);
            info.ancillaryBytes += length;
            info.hasAncillary = true;
        }
        p += 12 + length;
    }
    return InspectResult(Status.truncated);
}

/// Copies validated native PLTE RGB triples and tRNS payload without applying
/// colour or alpha semantics. Empty corresponding destinations are permitted
/// only when the chunk is absent.
Result readPngPaletteAndTransparency(scope const(ubyte)[] file,
    scope ubyte[] palette, scope ubyte[] transparency, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    const checked = inspectPng(file, limits);
    if (!checked.ok) return Result(checked.status);
    const info = checked.info;
    if (palette.length < cast(size_t)info.paletteEntries * 3 ||
        transparency.length < info.transparencyBytes)
        return Result(Status.destinationTooSmall);
    for (size_t p = 8; p < file.length; p += 12 + be32(file, p))
    {
        const length = cast(size_t)be32(file, p);
        const data = file[p + 8 .. p + 8 + length];
        if (file[p + 4 .. p + 8] == "PLTE") palette[0 .. length] = data;
        if (file[p + 4 .. p + 8] == "tRNS") transparency[0 .. length] = data;
    }
    return Result(Status.ok, cast(size_t)info.paletteEntries * 3 +
        info.transparencyBytes);
}

private ubyte paeth(ubyte a, ubyte b, ubyte c) @safe pure nothrow @nogc
{
    const p = cast(int)a + b - c;
    const da = p > a ? p - a : a - p;
    const db = p > b ? p - b : b - p;
    const dc = p > c ? p - c : c - p;
    return da <= db && da <= dc ? a : db <= dc ? b : c;
}

private Status unfilter(scope ubyte[] bytes, Info info) @safe pure nothrow @nogc
{
    const stride = info.rowBytes + 1;
    const bpp = (cast(size_t)info.channels * info.bitDepth + 7) / 8;
    foreach (size_t y; 0 .. info.height)
    {
        const p = y * stride;
        const filter = bytes[p];
        if (filter > 4) return Status.invalidFilter;
        foreach (size_t x; 0 .. info.rowBytes)
        {
            const left = x >= bpp ? bytes[p + 1 + x - bpp] : 0;
            const above = y != 0 ? bytes[p + 1 + x - stride] : 0;
            const upperLeft = y != 0 && x >= bpp ? bytes[p + 1 + x - stride - bpp] : 0;
            ubyte predictor;
            switch (filter)
            {
                case 0: predictor = 0; break;
                case 1: predictor = left; break;
                case 2: predictor = above; break;
                case 3: predictor = cast(ubyte)((cast(uint)left + above) / 2); break;
                case 4: predictor = paeth(left, above, upperLeft); break;
                default: assert(0);
            }
            bytes[p + 1 + x] += predictor;
        }
    }
    return Status.ok;
}

private Status unfilterRow(scope ubyte[] row, scope const(ubyte)[] previous,
    size_t bpp) @safe pure nothrow @nogc
{
    const filter = row[0];
    if (filter > 4) return Status.invalidFilter;
    foreach (size_t x; 0 .. row.length - 1)
    {
        const left = x >= bpp ? row[1 + x - bpp] : 0;
        const above = previous.length != 0 ? previous[x] : 0;
        const upperLeft = previous.length != 0 && x >= bpp ? previous[x - bpp] : 0;
        ubyte predictor;
        switch (filter)
        {
            case 0: predictor = 0; break;
            case 1: predictor = left; break;
            case 2: predictor = above; break;
            case 3: predictor = cast(ubyte)((cast(uint)left + above) / 2); break;
            case 4: predictor = paeth(left, above, upperLeft); break;
            default: assert(0);
        }
        row[1 + x] += predictor;
    }
    return Status.ok;
}

private bool validPaletteRow(scope const(ubyte)[] row, uint width,
    ubyte bitDepth, uint entries) @safe pure nothrow @nogc
{
    const mask = (1U << bitDepth) - 1;
    foreach (size_t x; 0 .. width)
    {
        const bit = x * bitDepth;
        const index = (row[bit / 8] >> (8 - bitDepth - bit % 8)) & mask;
        if (index >= entries) return false;
    }
    return true;
}

/// Decode IDAT slices without compressed/full-image staging. A codec or filter
/// failure can leave complete preceding rows visible; written reports those
/// sample bytes. Input and all caller-owned buffers must not alias.
Result decodePngRows(scope const(ubyte)[] file, scope ubyte[] currentRow,
    scope ubyte[] previousRow, scope ubyte[] destination, size_t rowStride,
    ref InflateWorkspace decoder, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    const inspected = inspectPng(file, limits);
    if (!inspected.ok) return Result(inspected.status);
    const info = inspected.info;
    if (currentRow.length < info.rowBytes + 1 || previousRow.length < info.rowBytes)
        return Result(Status.workspaceTooSmall);
    if (rowStride < info.rowBytes) return Result(Status.destinationTooSmall);
    if (info.height > 1 && rowStride > (size_t.max - info.rowBytes) / (info.height - 1))
        return Result(Status.sizeLimit);
    if ((cast(size_t)(info.height - 1) * rowStride + info.rowBytes) > destination.length)
        return Result(Status.destinationTooSmall);
    ZlibState state;
    state.reset(DecodeLimits(info.filteredBytes));
    size_t rowFill, rowsDone, totalInput;
    bool done;
    ubyte[1] overflow;
    for (size_t p = 8; p < file.length; p += 12 + be32(file, p))
    {
        const length = cast(size_t)be32(file, p);
        if (file[p + 4 .. p + 8] != "IDAT") continue;
        const data = file[p + 8 .. p + 8 + length];
        size_t cursor;
        while (cursor < data.length && !done)
        {
            ubyte[] outputRow = rowsDone < info.height ?
                currentRow[rowFill .. info.rowBytes + 1] : overflow[];
            auto result = decodeZlib(state, decoder, data[cursor .. $], outputRow);
            cursor += result.consumed;
            totalInput += result.consumed;
            if (rowsDone == info.height)
            {
                if (result.produced != 0)
                    return Result(Status.decodedSizeMismatch, rowsDone * info.rowBytes);
            }
            else
            {
                rowFill += result.produced;
                if (rowFill == info.rowBytes + 1)
                {
                    const status = unfilterRow(currentRow[0 .. rowFill],
                        rowsDone == 0 ? null : previousRow[0 .. info.rowBytes],
                        (cast(size_t)info.channels * info.bitDepth + 7) / 8);
                    if (status != Status.ok)
                        return Result(status, rowsDone * info.rowBytes);
                    if (info.colorType == 3 && !validPaletteRow(
                        currentRow[1 .. 1 + info.rowBytes], info.width,
                        info.bitDepth, info.paletteEntries))
                        return Result(Status.invalidInput, rowsDone * info.rowBytes);
                    destination[rowsDone * rowStride .. rowsDone * rowStride + info.rowBytes] =
                        currentRow[1 .. 1 + info.rowBytes];
                    previousRow[0 .. info.rowBytes] = currentRow[1 .. 1 + info.rowBytes];
                    ++rowsDone;
                    rowFill = 0;
                }
            }
            if (result.status == DecodeStatus.error)
                return Result(Status.codecError, rowsDone * info.rowBytes, result.error.code);
            if (result.status == DecodeStatus.done) done = true;
            if (result.status == DecodeStatus.needInput && cursor != data.length)
                return Result(Status.codecError, rowsDone * info.rowBytes);
            if (result.status == DecodeStatus.needOutput && result.produced == 0)
                return Result(Status.codecError, rowsDone * info.rowBytes);
        }
        if (done && cursor != data.length)
            return Result(Status.decodedSizeMismatch, rowsDone * info.rowBytes);
        if (done && length != 0 && cursor == 0)
            return Result(Status.decodedSizeMismatch, rowsDone * info.rowBytes);
    }
    if (!done)
    {
        ubyte[] outputRow = rowsDone < info.height ?
            currentRow[rowFill .. info.rowBytes + 1] : overflow[];
        const result = decodeZlib(state, decoder, null, outputRow, true);
        if (result.produced != 0 || result.status != DecodeStatus.done)
            return Result(Status.codecError, rowsDone * info.rowBytes, result.error.code);
        done = true;
    }
    if (totalInput != info.compressedBytes || rowsDone != info.height || rowFill != 0)
        return Result(Status.decodedSizeMismatch, rowsDone * info.rowBytes);
    return Result(Status.ok, rowsDone * info.rowBytes);
}

/// All validation and decode happen before writing caller-visible pixels.
Result decodePng(scope const(ubyte)[] file, scope ubyte[] compressed,
    scope ubyte[] filtered, scope ubyte[] destination, size_t rowStride,
    ref InflateWorkspace decoder, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    const inspected = inspectPng(file, limits);
    if (!inspected.ok) return Result(inspected.status);
    const info = inspected.info;
    if (compressed.length < info.compressedBytes || filtered.length < info.filteredBytes)
        return Result(Status.workspaceTooSmall);
    if (rowStride < info.rowBytes) return Result(Status.destinationTooSmall);
    if (rowStride && info.height > 1 &&
        rowStride > (size_t.max - info.rowBytes) / (info.height - 1))
        return Result(Status.sizeLimit);
    const visibleBytes = (cast(size_t)info.height - 1) * rowStride + info.rowBytes;
    if (visibleBytes > destination.length) return Result(Status.destinationTooSmall);
    size_t p = 8, copied;
    while (p < file.length)
    {
        const length = cast(size_t)be32(file, p);
        if (file[p + 4 .. p + 8] == "IDAT")
        {
            compressed[copied .. copied + length] = file[p + 8 .. p + 8 + length];
            copied += length;
        }
        p += 12 + length;
    }
    auto inflated = inflateZlib(compressed[0 .. copied], filtered[0 .. info.filteredBytes],
        decoder, DecodeLimits(info.filteredBytes));
    if (inflated.status != DecodeStatus.done)
        return Result(Status.codecError, 0, inflated.error.code);
    if (inflated.consumed != copied || inflated.produced != info.filteredBytes)
        return Result(Status.decodedSizeMismatch);
    const filterStatus = unfilter(filtered[0 .. info.filteredBytes], info);
    if (filterStatus != Status.ok) return Result(filterStatus);
    if (info.colorType == 3)
        foreach (size_t y; 0 .. info.height)
            if (!validPaletteRow(filtered[y * (info.rowBytes + 1) + 1 ..
                    y * (info.rowBytes + 1) + 1 + info.rowBytes],
                info.width, info.bitDepth, info.paletteEntries))
                return Result(Status.invalidInput);
    foreach (size_t y; 0 .. info.height)
        destination[y * rowStride .. y * rowStride + info.rowBytes] =
            filtered[y * (info.rowBytes + 1) + 1 ..
                y * (info.rowBytes + 1) + 1 + info.rowBytes];
    return Result(Status.ok, cast(size_t)info.height * info.rowBytes);
}

private void chunk(scope ubyte[] output, size_t p, scope const(ubyte)[] type,
    scope const(ubyte)[] data) @safe pure nothrow @nogc
{
    put32(output, p, cast(uint)data.length);
    output[p + 4 .. p + 8] = type;
    output[p + 8 .. p + 8 + data.length] = data;
    put32(output, p + 8 + data.length,
        crc32(output[p + 4 .. p + 8 + data.length]));
}

private ubyte filteredByte(ubyte kind, ubyte value, ubyte left,
    ubyte above, ubyte upperLeft) @safe pure nothrow @nogc
{
    uint predictor;
    switch (kind)
    {
        case 0: predictor = 0; break;
        case 1: predictor = left; break;
        case 2: predictor = above; break;
        case 3: predictor = (cast(uint)left + above) / 2; break;
        case 4: predictor = paeth(left, above, upperLeft); break;
        default: assert(0);
    }
    return cast(ubyte)(value - predictor);
}

private void filterAdaptiveRow(scope const(ubyte)[] current,
    scope const(ubyte)[] previous, size_t bpp, scope ubyte[] filtered)
    @safe pure nothrow @nogc
{
    ubyte best;
    ulong bestScore = ulong.max;
    foreach (ubyte kind; 0 .. 5)
    {
        ulong score;
        foreach (size_t x; 0 .. current.length)
        {
            const left = x >= bpp ? current[x - bpp] : 0;
            const above = previous.length != 0 ? previous[x] : 0;
            const upperLeft = previous.length != 0 && x >= bpp ? previous[x - bpp] : 0;
            const value = filteredByte(kind, current[x], left, above, upperLeft);
            score += value < 128 ? value : 256U - value;
        }
        if (score < bestScore) { bestScore = score; best = kind; }
    }
    filtered[0] = best;
    foreach (size_t x; 0 .. current.length)
    {
        const left = x >= bpp ? current[x - bpp] : 0;
        const above = previous.length != 0 ? previous[x] : 0;
        const upperLeft = previous.length != 0 && x >= bpp ? previous[x - bpp] : 0;
        filtered[x + 1] = filteredByte(best, current[x], left, above, upperLeft);
    }
}

/// Shared experiment body; the codec choice is compile-time and cannot hide
/// a nullable match-finder or allocate one in the fixed-LZ path.
private Result encodePngImpl(bool useHash, Finder)(Info info,
    scope const(ubyte)[] source, size_t rowStride,
    MetadataPolicy metadataPolicy, scope ubyte[] filtered, scope ubyte[] zlib,
    scope ubyte[] output, Limits limits, FilterStrategy filterStrategy,
    ref Finder finder)
    @safe pure nothrow @nogc
{
    const req = writeRequirements(info.width, info.height, info.bitDepth,
        info.colorType, limits);
    if (req.status != Status.ok) return Result(req.status);
    if (metadataPolicy != MetadataPolicy.rejectLoss && metadataPolicy != MetadataPolicy.drop)
        return Result(Status.invalidInput);
    if (filterStrategy != FilterStrategy.none && filterStrategy != FilterStrategy.adaptive)
        return Result(Status.invalidInput);
    if (info.hasAncillary && metadataPolicy == MetadataPolicy.rejectLoss)
        return Result(Status.metadataWouldBeLost);
    if (rowStride < req.rowBytes) return Result(Status.invalidInput);
    if (info.height > 1 && rowStride > (size_t.max - req.rowBytes) / (info.height - 1))
        return Result(Status.sizeLimit);
    if ((cast(size_t)(info.height - 1) * rowStride + req.rowBytes) > source.length)
        return Result(Status.truncated);
    if (filtered.length < req.filteredBytes || zlib.length < req.zlibCapacity)
        return Result(Status.workspaceTooSmall);
    if (output.length < req.pngCapacity) return Result(Status.destinationTooSmall);
    foreach (size_t y; 0 .. info.height)
    {
        const p = y * (req.rowBytes + 1);
        const current = source[y * rowStride .. y * rowStride + req.rowBytes];
        if (filterStrategy == FilterStrategy.adaptive)
        {
            const previous = y == 0 ? null :
                source[(y - 1) * rowStride .. (y - 1) * rowStride + req.rowBytes];
            filterAdaptiveRow(current, previous,
                cast(size_t)channelsFor(info.colorType) * (info.bitDepth / 8),
                filtered[p .. p + 1 + req.rowBytes]);
        }
        else
        {
            filtered[p] = 0;
            filtered[p + 1 .. p + 1 + req.rowBytes] = current;
        }
    }
    size_t compressedWritten;
    static if (useHash)
    {
        static assert(is(Finder == HashChainMatchFinder));
        const encoded = encodeZlibHashChain(finder,
            filtered[0 .. req.filteredBytes], zlib[0 .. req.zlibCapacity]);
        if (encoded.status != DecodeStatus.done)
            return Result(Status.codecError, 0, encoded.error.code);
        compressedWritten = encoded.produced;
    }
    else
    {
        const encoded = encodeZlibStored(filtered[0 .. req.filteredBytes],
            zlib[0 .. req.zlibCapacity]);
        if (encoded.status != DecodeStatus.done)
            return Result(Status.codecError, 0, encoded.error.code);
        compressedWritten = encoded.produced;
    }
    output[0 .. 8] = signature[];
    ubyte[13] ihdr;
    put32(ihdr[], 0, info.width); put32(ihdr[], 4, info.height);
    ihdr[8] = info.bitDepth; ihdr[9] = info.colorType;
    chunk(output, 8, cast(const(ubyte)[])"IHDR", ihdr[]);
    chunk(output, 33, cast(const(ubyte)[])"IDAT", zlib[0 .. compressedWritten]);
    const end = 45 + compressedWritten;
    chunk(output, end, cast(const(ubyte)[])"IEND", null);
    return Result(Status.ok, end + 12, ErrorCode.none, info.hasAncillary);
}

/// Writes filter-0 or adaptive scanlines using the provider's fixed-LZ zlib.
/// No implicit colour/radiometric conversion.
Result encodePng(Info info, scope const(ubyte)[] source, size_t rowStride,
    MetadataPolicy metadataPolicy, scope ubyte[] filtered, scope ubyte[] zlib,
    scope ubyte[] output, Limits limits = Limits.init,
    FilterStrategy filterStrategy = FilterStrategy.none)
    @safe pure nothrow @nogc
{
    ubyte unused;
    return encodePngImpl!false(info, source, rowStride, metadataPolicy,
        filtered, zlib, output, limits, filterStrategy, unused);
}

/// Fast research path with explicit, caller-owned match finder. Stack ownership
/// works in @safe code; the finder is reset for each independent PNG.
Result encodePngHashChain(Info info, scope const(ubyte)[] source,
    size_t rowStride, MetadataPolicy metadataPolicy, scope ubyte[] filtered,
    scope ubyte[] zlib, scope ubyte[] output, ref HashChainMatchFinder finder,
    Limits limits = Limits.init,
    FilterStrategy filterStrategy = FilterStrategy.adaptive)
    @safe pure nothrow @nogc
{
    return encodePngImpl!true(info, source, rowStride, metadataPolicy,
        filtered, zlib, output, limits, filterStrategy, finder);
}

private bool knownColorChunk(scope const(ubyte)[] type)
    @safe pure nothrow @nogc
{
    return type == "PLTE" || type == "tRNS" || type == "iCCP" ||
        type == "sRGB" || type == "gAMA" || type == "cHRM" ||
        type == "sBIT";
}

/// Conservative metadata transfer for a re-encoded image of the same shape.
/// Unknown unsafe-to-copy chunks are never copied after IDAT changes. Known
/// colour chunks require an explicit applicability assertion by the caller.
/// Source, basePng and output must not alias. basePng is caller-owned staging.
private Result encodePngWithMetadataImpl(bool useHash, Finder)(
    scope const(ubyte)[] original, Info info,
    scope const(ubyte)[] source, size_t rowStride, MetadataTransfer transfer,
    scope ubyte[] filtered, scope ubyte[] zlib, scope ubyte[] basePng,
    scope ubyte[] output, Limits limits, FilterStrategy filterStrategy,
    ref Finder finder)
    @safe pure nothrow @nogc
{
    const checked = inspectPng(original, limits);
    if (!checked.ok) return Result(checked.status);
    const old = checked.info;
    if (old.width != info.width || old.height != info.height ||
        old.bitDepth != info.bitDepth || old.colorType != info.colorType)
        return Result(Status.invalidInput);
    const req = writeRequirements(info.width, info.height, info.bitDepth,
        info.colorType, limits);
    if (req.status != Status.ok) return Result(req.status);
    if (basePng.length < req.pngCapacity) return Result(Status.workspaceTooSmall);
    size_t extra;
    bool dropped;
    for (size_t p = 8; p < original.length; p += 12 + be32(original, p))
    {
        const length = cast(size_t)be32(original, p);
        const type = original[p + 4 .. p + 8];
        if (type == "IHDR" || type == "IDAT" || type == "IEND") continue;
        const keep = knownColorChunk(type) ? transfer.colorMetadataStillApplies :
            (type[0] & 32) != 0 && (type[3] & 32) != 0;
        if (!keep)
        {
            if (!transfer.dropUnsupported) return Result(Status.metadataWouldBeLost);
            dropped = true;
            continue;
        }
        if (extra > size_t.max - length - 12) return Result(Status.sizeLimit);
        extra += length + 12;
    }
    if (req.pngCapacity > limits.maxFileBytes ||
        extra > limits.maxFileBytes - req.pngCapacity)
        return Result(Status.sizeLimit);
    if (output.length < req.pngCapacity + extra)
        return Result(Status.destinationTooSmall);
    Result encoded;
    static if (useHash)
        encoded = encodePngHashChain(info, source, rowStride,
            MetadataPolicy.drop, filtered, zlib, basePng, finder,
            limits, filterStrategy);
    else
        encoded = encodePng(info, source, rowStride, MetadataPolicy.drop,
            filtered, zlib, basePng, limits, filterStrategy);
    if (!encoded.ok) return encoded;
    // Reassemble around the single IDAT emitted by encodePng. All copied
    // chunks retain their original before/after-IDAT side and internal order.
    output[0 .. 33] = basePng[0 .. 33];
    size_t cursor = 33;
    bool afterData;
    foreach (pass; 0 .. 2)
    {
        for (size_t p = 8; p < original.length; p += 12 + be32(original, p))
        {
            const length = cast(size_t)be32(original, p);
            const type = original[p + 4 .. p + 8];
            if (type == "IDAT") afterData = true;
            if (type == "IHDR" || type == "IDAT" || type == "IEND") continue;
            if ((pass == 0 && afterData) || (pass == 1 && !afterData)) continue;
            const keep = knownColorChunk(type) ? transfer.colorMetadataStillApplies :
                (type[0] & 32) != 0 && (type[3] & 32) != 0;
            if (keep)
            {
                output[cursor .. cursor + length + 12] = original[p .. p + length + 12];
                cursor += length + 12;
            }
        }
        if (pass == 0)
        {
            const idatEnd = encoded.written - 12;
            output[cursor .. cursor + idatEnd - 33] = basePng[33 .. idatEnd];
            cursor += idatEnd - 33;
        }
        afterData = false;
    }
    output[cursor .. cursor + 12] = basePng[encoded.written - 12 .. encoded.written];
    cursor += 12;
    return Result(Status.ok, cursor, ErrorCode.none, dropped);
}

Result encodePngWithMetadata(scope const(ubyte)[] original, Info info,
    scope const(ubyte)[] source, size_t rowStride, MetadataTransfer transfer,
    scope ubyte[] filtered, scope ubyte[] zlib, scope ubyte[] basePng,
    scope ubyte[] output, Limits limits = Limits.init,
    FilterStrategy filterStrategy = FilterStrategy.adaptive)
    @safe pure nothrow @nogc
{
    ubyte unused;
    return encodePngWithMetadataImpl!false(original, info, source,
        rowStride, transfer, filtered, zlib, basePng, output, limits,
        filterStrategy, unused);
}

Result encodePngWithMetadataHashChain(scope const(ubyte)[] original,
    Info info, scope const(ubyte)[] source, size_t rowStride,
    MetadataTransfer transfer, scope ubyte[] filtered, scope ubyte[] zlib,
    scope ubyte[] basePng, scope ubyte[] output,
    ref HashChainMatchFinder finder, Limits limits = Limits.init,
    FilterStrategy filterStrategy = FilterStrategy.adaptive)
    @safe pure nothrow @nogc
{
    return encodePngWithMetadataImpl!true(original, info, source,
        rowStride, transfer, filtered, zlib, basePng, output, limits,
        filterStrategy, finder);
}

/// Research speed option: one stored DEFLATE block per row, no full-image
/// filtered/zlib staging. The entire PNG output is still caller-owned memory.
Result encodePngRowsStored(Info info, scope const(ubyte)[] source, size_t rowStride,
    MetadataPolicy metadataPolicy, scope ubyte[] rowScratch, scope ubyte[] output,
    Limits limits = Limits.init) @safe pure nothrow @nogc
{
    const req = storedRowRequirements(info.width, info.height, info.bitDepth,
        info.colorType, limits);
    if (req.status != Status.ok) return Result(req.status);
    if (metadataPolicy != MetadataPolicy.rejectLoss && metadataPolicy != MetadataPolicy.drop)
        return Result(Status.invalidInput);
    if (info.hasAncillary && metadataPolicy == MetadataPolicy.rejectLoss)
        return Result(Status.metadataWouldBeLost);
    if (rowStride < req.rowBytes) return Result(Status.invalidInput);
    if (info.height > 1 && rowStride > (size_t.max - req.rowBytes) / (info.height - 1))
        return Result(Status.sizeLimit);
    if ((cast(size_t)(info.height - 1) * rowStride + req.rowBytes) > source.length)
        return Result(Status.truncated);
    if (rowScratch.length < req.filteredBytes) return Result(Status.workspaceTooSmall);
    if (output.length < req.pngCapacity) return Result(Status.destinationTooSmall);
    output[0 .. 8] = signature[];
    ubyte[13] ihdr;
    put32(ihdr[], 0, info.width); put32(ihdr[], 4, info.height);
    ihdr[8] = info.bitDepth; ihdr[9] = info.colorType;
    chunk(output, 8, cast(const(ubyte)[])"IHDR", ihdr[]);
    const payloadLength = req.zlibCapacity;
    put32(output, 33, cast(uint)payloadLength);
    output[37 .. 41] = cast(const(ubyte)[])"IDAT";
    size_t p = 41;
    output[p++] = 0x78; output[p++] = 0x01;
    RawStoredEncoderState state;
    Adler32 checksum;
    foreach (size_t y; 0 .. info.height)
    {
        rowScratch[0] = 0;
        rowScratch[1 .. 1 + req.rowBytes] =
            source[y * rowStride .. y * rowStride + req.rowBytes];
        const encoded = encodeRawStoredChunk(state,
            rowScratch[0 .. req.filteredBytes],
            output[p .. p + rawStoredSize(req.filteredBytes)],
            y + 1 == info.height);
        if (encoded.status != DecodeStatus.done)
            return Result(Status.codecError, p, encoded.error.code);
        checksum.update(rowScratch[0 .. req.filteredBytes]);
        p += encoded.produced;
    }
    const adler = checksum.value;
    put32(output, p, adler); p += 4;
    if (p != 41 + payloadLength) return Result(Status.decodedSizeMismatch, p);
    put32(output, p, crc32(output[37 .. p])); p += 4;
    chunk(output, p, cast(const(ubyte)[])"IEND", null);
    return Result(Status.ok, p + 12, ErrorCode.none, info.hasAncillary);
}

/// Pull-style output prototype: one source row and one complete IDAT per call.
/// Each returned byte span can be flushed before the next call. A failed call
/// does not advance the state; an external sink failure cannot be rolled back.
struct StoredRowWriter
{
    private Info info;
    private uint nextRow;
    private RawStoredEncoderState raw;
    private Adler32 checksum;
    private bool initialized;
    @property bool done() const @safe pure nothrow @nogc
    { return initialized && nextRow == info.height; }
}

Status beginStoredRowWriter(ref StoredRowWriter writer, Info info,
    MetadataPolicy metadataPolicy, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    const req = storedRowRequirements(info.width, info.height, info.bitDepth,
        info.colorType, limits);
    if (req.status != Status.ok) return req.status;
    if (metadataPolicy != MetadataPolicy.rejectLoss && metadataPolicy != MetadataPolicy.drop)
        return Status.invalidInput;
    if (info.hasAncillary && metadataPolicy == MetadataPolicy.rejectLoss)
        return Status.metadataWouldBeLost;
    writer = StoredRowWriter.init;
    writer.info = info;
    writer.info.rowBytes = req.rowBytes;
    writer.initialized = true;
    return Status.ok;
}

size_t storedRowChunkCapacity(Info info) @safe pure nothrow @nogc
{
    const req = storedRowRequirements(info.width, info.height,
        info.bitDepth, info.colorType);
    if (req.status != Status.ok) return 0;
    // The first/last call may both apply when height == 1.
    return rawStoredSize(req.rowBytes + 1) + 2 + 4 + 12 + 33 + 12;
}

Result writeStoredRow(ref StoredRowWriter writer, scope const(ubyte)[] row,
    scope ubyte[] rowScratch, scope ubyte[] output) @safe pure nothrow @nogc
{
    if (!writer.initialized || writer.done) return Result(Status.invalidInput);
    const info = writer.info;
    const rowLength = info.rowBytes + 1;
    const first = writer.nextRow == 0;
    const last = writer.nextRow + 1 == info.height;
    const storedLength = rawStoredSize(rowLength);
    const payloadLength = storedLength + (first ? 2 : 0) + (last ? 4 : 0);
    const needed = (first ? 33 : 0) + 12 + payloadLength + (last ? 12 : 0);
    if (row.length < info.rowBytes) return Result(Status.truncated);
    if (rowScratch.length < rowLength) return Result(Status.workspaceTooSmall);
    if (output.length < needed) return Result(Status.destinationTooSmall);
    size_t p;
    if (first)
    {
        output[0 .. 8] = signature[];
        ubyte[13] ihdr;
        put32(ihdr[], 0, info.width); put32(ihdr[], 4, info.height);
        ihdr[8] = info.bitDepth; ihdr[9] = info.colorType;
        chunk(output, 8, cast(const(ubyte)[])"IHDR", ihdr[]);
        p = 33;
    }
    put32(output, p, cast(uint)payloadLength);
    output[p + 4 .. p + 8] = cast(const(ubyte)[])"IDAT";
    const chunkStart = p + 4;
    p += 8;
    if (first) { output[p++] = 0x78; output[p++] = 0x01; }
    rowScratch[0] = 0;
    rowScratch[1 .. rowLength] = row[0 .. info.rowBytes];
    auto encoded = encodeRawStoredChunk(writer.raw, rowScratch[0 .. rowLength],
        output[p .. p + storedLength], last);
    if (encoded.status != DecodeStatus.done)
        return Result(Status.codecError, 0, encoded.error.code);
    p += encoded.produced;
    writer.checksum.update(rowScratch[0 .. rowLength]);
    if (last) { put32(output, p, writer.checksum.value); p += 4; }
    put32(output, p, crc32(output[chunkStart .. p])); p += 4;
    if (last) { chunk(output, p, cast(const(ubyte)[])"IEND", null); p += 12; }
    ++writer.nextRow;
    return Result(Status.ok, p, ErrorCode.none, info.hasAncillary);
}
