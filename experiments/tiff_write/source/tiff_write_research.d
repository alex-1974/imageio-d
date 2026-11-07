/// Minimal classic-TIFF writer experiment. Not a public package or API.
module tiff_write_research;

enum Status : ubyte { ok, unsupported, sizeLimit, sourceTooSmall, destinationTooSmall }

struct Info
{
    uint width, height;
    ubyte channels, sampleBytes;
}

struct Requirements
{
    Status status;
    size_t rowBytes, fileBytes, pixelOffset;
}

struct Result
{
    Status status;
    size_t written;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

private void put16(scope ubyte[] output, size_t p, ushort value)
    @safe pure nothrow @nogc
{
    output[p] = cast(ubyte)value;
    output[p + 1] = cast(ubyte)(value >> 8);
}

private void put32(scope ubyte[] output, size_t p, uint value)
    @safe pure nothrow @nogc
{
    put16(output, p, cast(ushort)value);
    put16(output, p + 2, cast(ushort)(value >> 16));
}

Requirements requirements(Info info) @safe pure nothrow @nogc
{
    if (!info.width || !info.height || info.channels < 1 || info.channels > 4 ||
        (info.sampleBytes != 1 && info.sampleBytes != 2))
        return Requirements(Status.unsupported);
    const pixelBytes = cast(size_t)info.channels * info.sampleBytes;
    if (info.width > size_t.max / pixelBytes) return Requirements(Status.sizeLimit);
    const rowBytes = cast(size_t)info.width * pixelBytes;
    if (info.height > uint.max / rowBytes) return Requirements(Status.sizeLimit);
    const entries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    const ifdEnd = 8 + 2 + entries * 12 + 4;
    const bitsBytes = info.channels > 2 ? info.channels * 2U : 0U;
    const pixelOffset = ifdEnd + bitsBytes;
    const fileBytes = pixelOffset + cast(size_t)info.height * rowBytes;
    if (fileBytes > uint.max) return Requirements(Status.sizeLimit);
    return Requirements(Status.ok, rowBytes, fileBytes, pixelOffset);
}

private void entry(scope ubyte[] output, ref size_t p, ushort tag, ushort kind,
    uint count, uint value) @safe pure nothrow @nogc
{
    put16(output, p, tag);
    put16(output, p + 2, kind);
    put32(output, p + 4, count);
    put32(output, p + 8, value);
    p += 12;
}

/// Source samples are byte-interleaved and 16-bit samples are little-endian.
/// Caller owns source/output. No metadata or colour conversion is performed.
/// All preflight failures leave output unchanged.
Result writeClassicTiff(Info info, scope const(ubyte)[] source, size_t rowStride,
    scope ubyte[] output) @safe pure nothrow @nogc
{
    const req = requirements(info);
    if (req.status != Status.ok) return Result(req.status);
    if (rowStride < req.rowBytes) return Result(Status.sourceTooSmall);
    if (info.height > 1 && rowStride >
        (size_t.max - req.rowBytes) / (info.height - 1))
        return Result(Status.sizeLimit);
    if ((cast(size_t)(info.height - 1) * rowStride + req.rowBytes) > source.length)
        return Result(Status.sourceTooSmall);
    if (output.length < req.fileBytes) return Result(Status.destinationTooSmall);
    output[0] = 'I'; output[1] = 'I';
    put16(output, 2, 42);
    put32(output, 4, 8);
    const entries = info.channels == 2 || info.channels == 4 ? 11U : 10U;
    put16(output, 8, cast(ushort)entries);
    size_t p = 10;
    const bits = cast(uint)info.sampleBytes * 8;
    const bitsOffset = 8 + 2 + entries * 12 + 4;
    entry(output, p, 256, 4, 1, info.width); // ImageWidth
    entry(output, p, 257, 4, 1, info.height); // ImageLength
    entry(output, p, 258, 3, info.channels,
        info.channels == 1 ? bits : info.channels == 2 ? bits | (bits << 16) :
        cast(uint)bitsOffset);
    entry(output, p, 259, 3, 1, 1); // Compression=None
    entry(output, p, 262, 3, 1, info.channels <= 2 ? 1U : 2U); // Photometric
    entry(output, p, 273, 4, 1, cast(uint)req.pixelOffset); // StripOffsets
    entry(output, p, 277, 3, 1, info.channels); // SamplesPerPixel
    entry(output, p, 278, 4, 1, info.height); // RowsPerStrip
    entry(output, p, 279, 4, 1, cast(uint)(req.rowBytes * info.height));
    entry(output, p, 284, 3, 1, 1); // PlanarConfiguration=chunky
    if (entries == 11) entry(output, p, 338, 3, 1, 2); // unassociated alpha
    put32(output, p, 0); // no next IFD
    if (info.channels > 2)
        foreach (size_t i; 0 .. info.channels)
            put16(output, bitsOffset + i * 2, cast(ushort)bits);
    foreach (size_t y; 0 .. info.height)
        output[req.pixelOffset + y * req.rowBytes ..
            req.pixelOffset + (y + 1) * req.rowBytes] =
            source[y * rowStride .. y * rowStride + req.rowBytes];
    return Result(Status.ok, req.fileBytes);
}
