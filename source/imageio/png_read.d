/** PNG reader foundation using caller-owned output and codec workspace. */
module imageio.png_read;

import compression.checksum : crc32;
import compression.core : DecodeLimits, DecodeStatus;
import compression.deflate : InflateWorkspace;
import compression.zlib : inflateZlib;
import imageio.io : ImageReadError, ImageReadResult;

struct PngReadInfo
{
    uint width;
    uint height;
    ubyte bitDepth;
    ubyte colorType;
    size_t rowBytes;
    uint paletteEntries;
}

private uint be32(scope const(ubyte)[] b, size_t p) @safe pure nothrow @nogc
{ return (cast(uint)b[p] << 24) | (cast(uint)b[p + 1] << 16)
    | (cast(uint)b[p + 2] << 8) | b[p + 3]; }

private ubyte channels(ubyte t) @safe pure nothrow @nogc
{
    final switch (t) { case 0: return 1; case 2: return 3;
        case 4: return 2; case 6: return 4; }
}

private ubyte paeth(ubyte a, ubyte b, ubyte c) @safe pure nothrow @nogc
{
    const p = cast(int)a + b - c;
    const pa = p > a ? p - a : a - p;
    const pb = p > b ? p - b : b - p;
    const pc = p > c ? p - c : c - p;
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

private bool unfilterRow(scope ubyte[] row, scope const(ubyte)[] previous, size_t bpp)
@safe pure nothrow @nogc
{
    if (row.length == 0 || row[0] > 4) return false;
    const kind = row[0];
    foreach (size_t i; 1 .. row.length)
    {
        const left = i > bpp ? row[i - bpp] : 0;
        const above = previous.length == 0 ? 0 : previous[i - 1];
        const upperLeft = previous.length == 0 || i <= bpp ? 0 : previous[i - bpp - 1];
        final switch (kind)
        {
            case 0: break;
            case 1: row[i] += left; break;
            case 2: row[i] += above; break;
            case 3: row[i] += cast(ubyte)((cast(uint)left + above) / 2); break;
            case 4: row[i] += paeth(left, above, upperLeft); break;
        }
    }
    return true;
}

/** Inspect and decode a non-interlaced PNG into caller-owned pixel storage. */
ImageReadResult readPng(scope const(ubyte)[] file, scope ubyte[] destination,
    size_t rowStride, ref InflateWorkspace workspace,
    size_t maximumPixels = 64 * 1024 * 1024) @safe
{
    static immutable ubyte[8] sig = [137, 80, 78, 71, 13, 10, 26, 10];
    if (file.length < 8 || file[0 .. 8] != sig[])
        return ImageReadResult(ImageReadError.unsupportedFormat);
    if (file.length < 33 || file[12 .. 16] != cast(const(ubyte)[])"IHDR")
        return ImageReadResult(ImageReadError.malformedInput);
    const width = be32(file, 16), height = be32(file, 20);
    const depth = file[24], type = file[25], interlace = file[28];
    const validDepth = type == 0 ? (depth == 1 || depth == 2 || depth == 4
        || depth == 8 || depth == 16) : type == 3
        ? (depth == 1 || depth == 2 || depth == 4 || depth == 8)
        : (depth == 8 || depth == 16);
    if (width == 0 || height == 0 || cast(ulong)width * height > maximumPixels
        || interlace != 0 || !validDepth
        || (type != 0 && type != 2 && type != 3 && type != 4 && type != 6))
        return ImageReadResult(ImageReadError.unsupportedRepresentation);
    const rowBits = cast(size_t)width * (type == 3 ? 1 : channels(type)) * depth;
    const rowBytes = (rowBits + 7) / 8;
    if (rowStride < rowBytes || cast(size_t)(height - 1) * rowStride + rowBytes > destination.length)
        return ImageReadResult(ImageReadError.sizeLimit);
    size_t idatBytes;
    uint paletteEntries;
    bool paletteSeen;
    for (size_t p = 8; p < file.length;)
    {
        if (file.length - p < 12) return ImageReadResult(ImageReadError.truncatedInput);
        const length = cast(size_t)be32(file, p);
        if (length > file.length - p - 12) return ImageReadResult(ImageReadError.truncatedInput);
        const end = p + 12 + length;
        const data = file[p + 8 .. p + 8 + length];
        if (file[p + 4 .. p + 8] == cast(const(ubyte)[])"IHDR"
            || file[p + 4 .. p + 8] == cast(const(ubyte)[])"IDAT")
            if (crc32(file[p + 4 .. p + 8 + length]) != be32(file, p + 8 + length))
                return ImageReadResult(ImageReadError.checksumFailure);
        if (file[p + 4 .. p + 8] == cast(const(ubyte)[])"IDAT")
            idatBytes += data.length;
        if (file[p + 4 .. p + 8] == cast(const(ubyte)[])"PLTE")
        {
            if (length == 0 || length % 3 != 0 || length > 256 * 3)
                return ImageReadResult(ImageReadError.malformedInput);
            paletteEntries = cast(uint)(length / 3);
            paletteSeen = true;
        }
        p = end;
    }
    if (type == 3 && !paletteSeen)
        return ImageReadResult(ImageReadError.malformedInput);
    auto compressed = new ubyte[](idatBytes);
    size_t copied;
    for (size_t p = 8; p < file.length;)
    {
        const length = cast(size_t)be32(file, p);
        if (file[p + 4 .. p + 8] == cast(const(ubyte)[])"IDAT")
        { compressed[copied .. copied + length] = file[p + 8 .. p + 8 + length]; copied += length; }
        p += 12 + length;
    }
    const filteredBytes = cast(size_t)height * (rowBytes + 1);
    auto filtered = new ubyte[](filteredBytes);
    auto inflated = inflateZlib(compressed[], filtered[], workspace,
        DecodeLimits(filteredBytes));
    if (inflated.status != DecodeStatus.done || inflated.produced != filteredBytes)
        return ImageReadResult(ImageReadError.codecFailure);
    auto previous = new ubyte[](rowBytes);
    const bpp = (cast(size_t)(type == 3 ? 1 : channels(type)) * depth + 7) / 8;
    foreach (size_t y; 0 .. height)
    {
        auto row = filtered[y * (rowBytes + 1) .. (y + 1) * (rowBytes + 1)];
        if (!unfilterRow(row, y == 0 ? null : previous[], bpp))
            return ImageReadResult(ImageReadError.malformedInput, y * rowBytes);
        destination[y * rowStride .. y * rowStride + rowBytes] = row[1 .. $];
        previous[] = row[1 .. $];
    }
    return ImageReadResult(ImageReadError.none, cast(size_t)height * rowBytes);
}

version (unittest)
{
    @safe unittest
    {
        import compression.deflate : InflateWorkspace;
        import imageio.png_write : PngWriteInfo, writePng;
        import imageio.io : ImageWriteOptions, MetadataPolicy;
        import transport : MemorySink;
        ubyte[6] source = [255, 0, 0, 0, 255, 0];
        auto sink = new MemorySink();
        auto written = writePng(sink, PngWriteInfo(2, 1, 8, 2), source[], 6,
            ImageWriteOptions(MetadataPolicy.allowLoss, 4096));
        assert(written.complete);
        ubyte[6] decoded;
        InflateWorkspace workspace;
        auto read = readPng(sink.data, decoded[], 6, workspace);
        assert(read.complete && read.bytesProduced == decoded.length);
        assert(decoded[] == source[]);
    }
}
