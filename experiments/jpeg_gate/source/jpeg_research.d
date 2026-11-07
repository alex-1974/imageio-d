/// Bounded Pure-D baseline JPEG 8-bit research codec; no public API.
/// RGB8 transforms here are oracle conveniences, not the intended colour API.
module jpeg_research;

enum Status : ubyte
{
    ok, truncated, invalid, unsupported, limit, destinationTooSmall
}

struct Info
{
    uint width, height;
    ubyte components;
}

struct Result
{
    Status status;
    Info info;
    size_t written;
    MetadataDisposition metadataDisposition;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

struct Limits
{
    size_t maxFileBytes = 64 * 1024 * 1024;
    ulong maxPixels = 64_000_000;
}

struct EncodeOptions
{
    /// De-facto JPEG quality scale, 1 (coarse) through 100 (finest).
    ubyte quality = 75;
    Sampling sampling = Sampling.s444;
    ushort restartInterval = 0; // MCU count; zero disables RST markers.
    MetadataPolicy metadataPolicy = MetadataPolicy.reject;
}

enum Sampling : ubyte { s444, s422, s420 }
enum MetadataPolicy : ubyte { reject, discard, copy }
enum MetadataDisposition : ubyte { none, copied, discarded }

/// Borrowed, caller-owned component planes. Chroma dimensions are ceil of
/// luma dimensions divided by the declared horizontal/vertical factors.
struct ConstPlane
{
    const(ubyte)[] bytes;
    size_t rowStride;
}

struct MutablePlane
{
    ubyte[] bytes;
    size_t rowStride;
}

private bool planeFits(size_t width, size_t height, size_t stride,
    size_t length) @safe pure nothrow @nogc
{
    return width != 0 && height != 0 && stride >= width &&
        (height == 1 || stride <= (size_t.max - width) / (height - 1)) &&
        (height - 1) * stride + width <= length;
}

/// Opaque JPEG EXIF APP1 payload (including Exif\0\0) and ICC profile bytes.
struct EncodeMetadata
{
    const(ubyte)[] exif;
    const(ubyte)[] icc;
}

struct MetadataSegment
{
    size_t offset, length;
}

struct MetadataResult
{
    Status status;
    size_t exifOffset, exifLength, iccBytes;
    ubyte iccSegments;
    size_t opaqueSegments, opaqueBytes;
    size_t containerLossSegments, containerLossBytes;
    @property bool ok() const @safe pure nothrow @nogc
    { return status == Status.ok; }
}

enum ComponentSignal : ubyte { gray, jfifYCbCr, adobeYCbCr, adobeRGB, unknown }

struct FrameResult
{
    Status status;
    Info info;
    ComponentSignal signal;
    ubyte[3] ids;
    ubyte[3] horizontal;
    ubyte[3] vertical;
    @property bool ok() const @safe pure nothrow @nogc
    { return status == Status.ok; }
}

/// Bounded pre-scan inspection only. Signal is a declaration, not a colour
/// conversion. Unknown three-component input must not be guessed as YCbCr.
FrameResult inspectJpegFrame(scope const(ubyte)[] file,
    Limits limits = Limits.init) @safe pure nothrow @nogc
{
    if (file.length > limits.maxFileBytes) return FrameResult(Status.limit);
    if (file.length < 4 || file[0] != 0xff || file[1] != 0xd8)
        return FrameResult(Status.invalid);
    FrameResult result;
    bool frameSeen, jfifSeen;
    int adobeTransform = -1;
    size_t p = 2;
    while (p < file.length)
    {
        if (file[p++] != 0xff) return FrameResult(Status.invalid);
        while (p < file.length && file[p] == 0xff) ++p;
        if (p >= file.length) return FrameResult(Status.truncated);
        const marker = file[p++];
        if (marker == 0xd9) return FrameResult(Status.invalid);
        if (file.length - p < 2) return FrameResult(Status.truncated);
        const length = be16(file, p);
        if (length < 2 || length > file.length - p)
            return FrameResult(Status.truncated);
        const end = p + length;
        p += 2;
        if (marker == 0xe0 && p == 6 && end - p >= 5 &&
            file[p .. p + 5] == cast(const(ubyte)[])"JFIF\0")
            jfifSeen = true;
        else if (marker == 0xee && end - p >= 12 &&
            file[p .. p + 5] == cast(const(ubyte)[])"Adobe")
            adobeTransform = file[p + 11];
        else if (marker == 0xc0)
        {
            if (frameSeen || end - p < 6 || file[p] != 8)
                return FrameResult(Status.unsupported);
            result.info.height = be16(file, p + 1);
            result.info.width = be16(file, p + 3);
            result.info.components = file[p + 5];
            if (!result.info.width || !result.info.height ||
                cast(ulong)result.info.width * result.info.height > limits.maxPixels)
                return FrameResult(Status.limit);
            if ((result.info.components != 1 && result.info.components != 3) ||
                end - p != 6 + cast(size_t)result.info.components * 3)
                return FrameResult(Status.unsupported);
            p += 6;
            foreach (size_t c; 0 .. result.info.components)
            {
                result.ids[c] = file[p++];
                const sampling = file[p++];
                result.horizontal[c] = sampling >> 4;
                result.vertical[c] = sampling & 15;
                if (result.horizontal[c] == 0 || result.vertical[c] == 0)
                    return FrameResult(Status.invalid);
                ++p;
            }
            frameSeen = true;
        }
        else if (marker == 0xda)
        {
            if (!frameSeen) return FrameResult(Status.invalid);
            result.signal = result.info.components == 1 ? ComponentSignal.gray :
                adobeTransform == 0 ? ComponentSignal.adobeRGB :
                adobeTransform == 1 ? ComponentSignal.adobeYCbCr :
                adobeTransform >= 0 ? ComponentSignal.unknown :
                jfifSeen ? ComponentSignal.jfifYCbCr : ComponentSignal.unknown;
            result.status = Status.ok;
            return result;
        }
        p = end;
    }
    return FrameResult(Status.truncated);
}

/// Inspect pre-scan APP1/APP2 payloads and count other APP/COM payloads.
/// Non-default JFIF APP0 and Adobe APP14 carry technical fields the current
/// writer cannot preserve; count them separately as container-loss risks.
/// Returned offsets borrow `file`.
/// ICC segment descriptors are written in reassembly order to caller storage.
/// No EXIF orientation or ICC colour semantics are applied.
MetadataResult inspectJpegMetadata(scope const(ubyte)[] file,
    scope MetadataSegment[] iccSegments, Limits limits = Limits.init)
    @safe pure nothrow @nogc
{
    if (file.length > limits.maxFileBytes) return MetadataResult(Status.limit);
    if (file.length < 4 || file[0] != 0xff || file[1] != 0xd8)
        return MetadataResult(Status.invalid);
    MetadataSegment[255] ordered;
    bool[255] seen;
    MetadataResult result;
    size_t p = 2;
    while (p < file.length)
    {
        if (file[p++] != 0xff) return MetadataResult(Status.invalid);
        while (p < file.length && file[p] == 0xff) ++p;
        if (p >= file.length) return MetadataResult(Status.truncated);
        const marker = file[p++];
        if (marker == 0xd9) return MetadataResult(Status.invalid);
        if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7)
            return MetadataResult(Status.invalid);
        if (file.length - p < 2) return MetadataResult(Status.truncated);
        const length = be16(file, p);
        if (length < 2 || length > file.length - p)
            return MetadataResult(Status.truncated);
        const end = p + length;
        p += 2;
        bool recognized;
        if (marker == 0xda)
        {
            if (length < 6) return MetadataResult(Status.invalid);
            foreach (size_t i; 0 .. result.iccSegments)
                if (!seen[i]) return MetadataResult(Status.invalid);
            if (iccSegments.length < result.iccSegments)
                return MetadataResult(Status.destinationTooSmall);
            foreach (size_t i; 0 .. result.iccSegments)
                iccSegments[i] = ordered[i];
            result.status = Status.ok;
            return result;
        }
        if (marker == 0xe1 && end - p >= 6 &&
            file[p .. p + 6] == cast(const(ubyte)[])"Exif\0\0")
        {
            if (result.exifLength != 0) return MetadataResult(Status.invalid);
            result.exifOffset = p;
            result.exifLength = end - p;
            recognized = true;
        }
        if (marker == 0xe2 && end - p >= 14 &&
            file[p .. p + 12] == cast(const(ubyte)[])"ICC_PROFILE\0")
        {
            const sequence = file[p + 12], count = file[p + 13];
            if (sequence == 0 || count == 0 || sequence > count ||
                result.iccSegments != 0 && result.iccSegments != count ||
                seen[sequence - 1])
                return MetadataResult(Status.invalid);
            result.iccSegments = count;
            seen[sequence - 1] = true;
            ordered[sequence - 1] = MetadataSegment(p + 14, end - p - 14);
            result.iccBytes += end - p - 14;
            if (result.iccBytes > limits.maxFileBytes)
                return MetadataResult(Status.limit);
            recognized = true;
        }
        if (marker == 0xe0 && end - p >= 5 &&
            file[p .. p + 5] == cast(const(ubyte)[])"JFIF\0")
        {
            recognized = true;
            // Only this writer's density=1, no-thumbnail JFIF payload is
            // recreated unchanged. All other JFIF fields require policy.
            if (p != 6 || end - p != 14 || file[p + 5] != 1 || file[p + 6] != 1 ||
                file[p + 7] != 0 || be16(file, p + 8) != 1 ||
                be16(file, p + 10) != 1 || file[p + 12] != 0 ||
                file[p + 13] != 0)
            {
                ++result.containerLossSegments;
                result.containerLossBytes += end - p;
            }
        }
        if (marker == 0xee && end - p >= 5 &&
            file[p .. p + 5] == cast(const(ubyte)[])"Adobe")
        {
            recognized = true;
            ++result.containerLossSegments;
            result.containerLossBytes += end - p;
        }
        if ((marker >= 0xe0 && marker <= 0xef || marker == 0xfe) &&
            !recognized)
        {
            ++result.opaqueSegments;
            result.opaqueBytes += end - p;
        }
        p = end;
    }
    return MetadataResult(Status.truncated);
}

// Reference JPEG quantizers in natural (not zigzag) coefficient order.
private immutable ubyte[64] lumaBase = [
    16,11,10,16,24,40,51,61, 12,12,14,19,26,58,60,55,
    14,13,16,24,40,57,69,56, 14,17,22,29,51,87,80,62,
    18,22,37,56,68,109,103,77, 24,35,55,64,81,104,113,92,
    49,64,78,87,103,121,120,101, 72,92,95,98,112,100,103,99];
private immutable ubyte[64] chromaBase = [
    17,18,24,47,99,99,99,99, 18,21,26,66,99,99,99,99,
    24,26,56,99,99,99,99,99, 47,66,99,99,99,99,99,99,
    99,99,99,99,99,99,99,99, 99,99,99,99,99,99,99,99,
    99,99,99,99,99,99,99,99, 99,99,99,99,99,99,99,99];

private void quantTable(ref ubyte[64] table, ref const(ubyte[64]) base,
    ubyte quality) @safe pure nothrow @nogc
{
    const scale = quality < 50 ? 5000U / quality : 200U - 2U * quality;
    foreach (size_t i; 0 .. 64)
    {
        const value = (cast(uint)base[i] * scale + 50) / 100;
        table[i] = cast(ubyte)(value < 1 ? 1 : value > 255 ? 255 : value);
    }
}

private immutable ubyte[64] zig = [
    0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
    12,19,26,33,40,48,41,34,27,20,13,6,7,14,
    21,28,35,42,49,56,57,50,43,36,29,22,15,
    23,30,37,44,51,58,59,52,45,38,31,39,46,53,
    60,61,54,47,55,62,63];

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

private ushort be16(scope const(ubyte)[] data, size_t p)
    @safe pure nothrow @nogc
{ return cast(ushort)((cast(uint)data[p] << 8) | data[p + 1]); }

private struct Huff
{
    ubyte[16] counts;
    ubyte[256] symbols;
    ushort[16] firstCode;
    ushort[16] firstIndex;
    ushort[256] codes;
    ubyte[256] lengths;
    ushort total;
    bool valid;
}

private bool build(ref Huff table) @safe pure nothrow @nogc
{
    uint code, index;
    foreach (size_t i; 0 .. 16)
    {
        table.firstCode[i] = cast(ushort)code;
        table.firstIndex[i] = cast(ushort)index;
        const count = table.counts[i];
        // JPEG reserves an all-ones code for padding/marker disambiguation.
        if (index + count > 256 || code + count >= (1U << (i + 1)))
            return false;
        foreach (size_t n; 0 .. count)
        {
            const value = table.symbols[index + n];
            if (table.lengths[value] != 0) return false;
            table.lengths[value] = cast(ubyte)(i + 1);
            table.codes[value] = cast(ushort)(code + n);
        }
        index += count;
        code = (code + count) << 1;
    }
    table.total = cast(ushort)index;
    table.valid = index != 0;
    return table.valid;
}

private struct Bits
{
    const(ubyte)[] data;
    size_t pos;
    uint buffer;
    ubyte remaining;
    bool bad;

    int bit() @safe pure nothrow @nogc
    {
        if (remaining == 0)
        {
            if (pos >= data.length) { bad = true; return 0; }
            buffer = data[pos++];
            if (buffer == 0xff)
            {
                if (pos >= data.length || data[pos++] != 0x00)
                { bad = true; return 0; }
            }
            remaining = 8;
        }
        --remaining;
        return cast(int)((buffer >> remaining) & 1);
    }

    int bits(uint count) @safe pure nothrow @nogc
    {
        int value;
        foreach (_; 0 .. count) value = (value << 1) | bit();
        return value;
    }
}

private int symbol(ref Bits reader, ref Huff table) @safe pure nothrow @nogc
{
    uint code;
    foreach (size_t i; 0 .. 16)
    {
        code = (code << 1) | reader.bit();
        if (reader.bad) return -1;
        const first = table.firstCode[i];
        const count = table.counts[i];
        if (code >= first && code - first < count)
            return table.symbols[table.firstIndex[i] + code - first];
    }
    return -1;
}

private int signedValue(ref Bits reader, uint count) @safe pure nothrow @nogc
{
    if (count == 0) return 0;
    const value = reader.bits(count);
    return value < (1 << (count - 1)) ? value - ((1 << count) - 1) : value;
}

private ubyte clamp(double value) @safe pure nothrow @nogc
{
    const rounded = cast(int)(value + (value >= 0 ? 0.5 : -0.5));
    return cast(ubyte)(rounded < 0 ? 0 : rounded > 255 ? 255 : rounded);
}

private void idct(ref int[64] coefficients, ref ubyte[64] samples)
    @safe pure nothrow @nogc
{
    double[64] horizontal;
    version (JpegIdctSparse)
    {
        // AC coefficients are usually sparse. Preserve the ascending-u
        // summation order of the dense path while skipping zero terms.
        horizontal[] = 0;
        foreach (size_t v; 0 .. 8)
            foreach (size_t u; 0 .. 8)
            {
                const coefficient = coefficients[v * 8 + u];
                if (coefficient == 0) continue;
                foreach (size_t x; 0 .. 8)
                    horizontal[v * 8 + x] += basis[u][x] * coefficient;
            }
    }
    else
    {
        foreach (size_t v; 0 .. 8)
            foreach (size_t x; 0 .. 8)
            {
                double value = 0;
                foreach (size_t u; 0 .. 8)
                    value += basis[u][x] * coefficients[v * 8 + u];
                horizontal[v * 8 + x] = value;
            }
    }
    foreach (size_t y; 0 .. 8)
        foreach (size_t x; 0 .. 8)
        {
            double value = 128;
            foreach (size_t v; 0 .. 8)
                value += basis[v][y] * horizontal[v * 8 + x];
            samples[y * 8 + x] = clamp(value);
        }
}

// The first pass leaves Y and representative Cb/Cr samples in the caller's
// RGB-sized output.
// Convert only after the complete entropy stream has passed validation. JPEG
// dimensions are 16-bit, so two interleaved Cb/Cr rows fit in 65_536 bytes.
private void convertSubsampled(scope ubyte[] destination, size_t width,
    size_t height, size_t rowStride, ubyte vFactor)
    @safe pure nothrow @nogc
{
    ubyte[65_536] previous, current;
    const columns = (width + 1) / 2;
    const rows = (height + vFactor - 1) / vFactor;
    foreach (size_t cy; 0 .. rows)
    {
        const sourceY = cy * vFactor;
        foreach (size_t cx; 0 .. columns)
        {
            const source = sourceY * rowStride + cx * 6;
            current[cx * 2] = destination[source + 1];
            current[cx * 2 + 1] = destination[source + 2];
        }
        foreach (size_t subY; 0 .. vFactor)
        {
            const y = sourceY + subY;
            if (y >= height) break;
            const previousY = vFactor == 2 && subY == 0 && cy > 0;
            const nextY = vFactor == 2 && subY == 1 && cy + 1 < rows;
            foreach (size_t x; 0 .. width)
            {
                const cx = x / 2;
                const nx = x % 2 == 0 ? (cx == 0 ? 0 : cx - 1) :
                    (cx + 1 == columns ? cx : cx + 1);
                const dest = y * rowStride + x * 3;
                double[2] chroma;
                foreach (size_t channel; 0 .. 2)
                {
                    const center = cast(uint)current[cx * 2 + channel];
                    const horizontal = cast(uint)current[nx * 2 + channel];
                    uint value;
                    if (vFactor == 1)
                        value = (3 * center + horizontal + 2) / 4;
                    else
                    {
                        uint vertical = center, diagonal = horizontal;
                        if (previousY)
                        {
                            vertical = previous[cx * 2 + channel];
                            diagonal = previous[nx * 2 + channel];
                        }
                        else if (nextY)
                        {
                            const next = (cy + 1) * 2 * rowStride;
                            vertical = destination[next + cx * 6 + 1 + channel];
                            diagonal = destination[next + nx * 6 + 1 + channel];
                        }
                        value = (9 * center + 3 * horizontal +
                            3 * vertical + diagonal + 8) / 16;
                    }
                    chroma[channel] = cast(double)value - 128;
                }
                const yy = cast(double)destination[dest];
                destination[dest] = clamp(yy + 1.402 * chroma[1]);
                destination[dest + 1] = clamp(yy - 0.344136 * chroma[0] -
                    0.714136 * chroma[1]);
                destination[dest + 2] = clamp(yy + 1.772 * chroma[0]);
            }
        }
        previous[0 .. columns * 2] = current[0 .. columns * 2];
    }
}

private void fdct(ref ubyte[64] samples, ref const(ubyte[64]) quant,
    ref int[64] coefficients)
    @safe pure nothrow @nogc
{
    double[64] horizontal;
    foreach (size_t y; 0 .. 8)
        foreach (size_t u; 0 .. 8)
        {
            double value = 0;
            foreach (size_t x; 0 .. 8)
                value += basis[u][x] * (cast(int)samples[y * 8 + x] - 128);
            horizontal[y * 8 + u] = value;
        }
    foreach (size_t v; 0 .. 8)
        foreach (size_t u; 0 .. 8)
        {
            double value = 0;
            foreach (size_t y; 0 .. 8)
                value += basis[v][y] * horizontal[y * 8 + u];
            value /= quant[v * 8 + u];
            int rounded = cast(int)(value + (value >= 0 ? 0.5 : -0.5));
            // Baseline 8-bit JPEG permits at most ten amplitude bits for AC.
            // Q=100 can otherwise create out-of-range coefficients.
            if (u != 0 || v != 0)
            {
                if (rounded > 1023) rounded = 1023;
                else if (rounded < -1023) rounded = -1023;
            }
            coefficients[v * 8 + u] = rounded;
        }
}

private struct Writer
{
    ubyte[] bytes;
    size_t pos;
    uint bitBuffer;
    ubyte bitCount;

    void putByte(ubyte value) scope @safe pure nothrow @nogc
    { bytes[pos++] = value; }
    void word(ushort value) scope @safe pure nothrow @nogc
    { putByte(cast(ubyte)(value >> 8)); putByte(cast(ubyte)value); }
    void marker(ubyte value) scope @safe pure nothrow @nogc
    { putByte(0xff); putByte(value); }
    void emit(uint value, uint count) scope @safe pure nothrow @nogc
    {
        version (JpegBitWriterLegacy)
        {
            foreach_reverse (uint bit; 0 .. count)
            {
                bitBuffer = (bitBuffer << 1) | ((value >> bit) & 1);
                if (++bitCount == 8)
                {
                    putByte(cast(ubyte)bitBuffer);
                    if (cast(ubyte)bitBuffer == 0xff) putByte(0);
                    bitBuffer = 0; bitCount = 0;
                }
            }
        }
        else
        {
            if (count == 0) return;
            // Huffman codes are at most 16 bits, and magnitude payloads at most
            // 11 bits. Together with fewer than 8 pending bits this fits in uint.
            bitBuffer = (bitBuffer << count) | (value & ((1U << count) - 1));
            bitCount += cast(ubyte)count;
            while (bitCount >= 8)
            {
                bitCount -= 8;
                const emitted = cast(ubyte)(bitBuffer >> bitCount);
                putByte(emitted);
                if (emitted == 0xff) putByte(0);
            }
            bitBuffer &= (1U << bitCount) - 1;
        }
    }
    void flushBits() scope @safe pure nothrow @nogc
    { if (bitCount) emit((1U << (8 - bitCount)) - 1, 8 - bitCount); }
}

private void writeHuff(ref Writer writer, ubyte tableClass, ref Huff table)
    @safe pure nothrow @nogc
{
    writer.marker(0xc4);
    writer.word(cast(ushort)(2 + 1 + 16 + table.total));
    writer.putByte(tableClass);
    foreach (count; table.counts) writer.putByte(count);
    foreach (size_t i; 0 .. table.total) writer.putByte(table.symbols[i]);
}

private bool emitSymbol(ref Writer writer, ref Huff table, ubyte value)
    @safe pure nothrow @nogc
{
    const length = table.lengths[value];
    if (length == 0) return false;
    writer.emit(table.codes[value], length);
    return true;
}

private uint magnitude(int value) @safe pure nothrow @nogc
{
    uint absolute = cast(uint)(value < 0 ? -value : value);
    uint bits;
    while (absolute) { ++bits; absolute >>= 1; }
    return bits;
}

private void emitValue(ref Writer writer, int value, uint bits)
    @safe pure nothrow @nogc
{
    if (bits) writer.emit(cast(uint)(value < 0 ? value - 1 : value), bits);
}

private bool writeBlock(ref Writer writer, ref int[64] coeff,
    ref int predictor, ref Huff dc, ref Huff ac) @safe pure nothrow @nogc
{
    const delta = coeff[0] - predictor;
    predictor = coeff[0];
    const dcBits = magnitude(delta);
    if (dcBits > 11 || !emitSymbol(writer, dc, cast(ubyte)dcBits)) return false;
    emitValue(writer, delta, dcBits);
    uint run;
    foreach (size_t k; 1 .. 64)
    {
        const value = coeff[zig[k]];
        if (value == 0) { ++run; continue; }
        while (run >= 16)
        {
            if (!emitSymbol(writer, ac, 0xf0)) return false;
            run -= 16;
        }
        const size = magnitude(value);
        if (size > 10 || !emitSymbol(writer, ac,
            cast(ubyte)((run << 4) | size))) return false;
        emitValue(writer, value, size);
        run = 0;
    }
    if (run && !emitSymbol(writer, ac, 0)) return false;
    return true;
}

/// Caller-owned output. Non-optimal canonical Huffman tables make this an
/// interoperability probe, not a quality/throughput claim. Metadata transfer
/// is opt-in; source semantics and orientation are never applied here.
/// RGB input is transformed to YCbCr; gray input remains gray.
Result encodeJpeg(Info info, scope const(ubyte)[] source, size_t rowStride,
    scope ubyte[] output, EncodeOptions options = EncodeOptions.init,
    scope EncodeMetadata metadata = EncodeMetadata.init,
    Limits limits = Limits.init, scope ubyte[] sampleTrace = null,
    scope int[] coefficientTrace = null,
    scope const(ConstPlane)[] sourcePlanes = null)
    @safe pure nothrow @nogc
{
    if (options.quality < 1 || options.quality > 100)
        return Result(Status.invalid);
    if (options.sampling > Sampling.s420 ||
        (info.components == 1 && options.sampling != Sampling.s444))
        return Result(Status.unsupported);
    if (options.metadataPolicy > MetadataPolicy.copy)
        return Result(Status.invalid);
    const hasMetadata = metadata.exif.length != 0 || metadata.icc.length != 0;
    if (hasMetadata && options.metadataPolicy == MetadataPolicy.reject)
        return Result(Status.unsupported);
    size_t metadataBytes;
    size_t iccSegments;
    if (hasMetadata && options.metadataPolicy == MetadataPolicy.copy)
    {
        if (metadata.exif.length != 0)
        {
            if (metadata.exif.length < 6 || metadata.exif.length > 65533 ||
                metadata.exif[0 .. 6] != cast(const(ubyte)[])"Exif\0\0")
                return Result(Status.invalid);
            metadataBytes += 4 + metadata.exif.length;
        }
        if (metadata.icc.length != 0)
        {
            if (metadata.icc.length < 128 || metadata.icc.length > 65519 * 255 ||
                metadata.icc[36 .. 40] != cast(const(ubyte)[])"acsp" ||
                (cast(uint)metadata.icc[0] << 24 |
                 cast(uint)metadata.icc[1] << 16 |
                 cast(uint)metadata.icc[2] << 8 |
                 metadata.icc[3]) != metadata.icc.length)
                return Result(Status.invalid);
            iccSegments = (metadata.icc.length + 65518) / 65519;
            metadataBytes += metadata.icc.length + iccSegments * 18;
        }
    }
    if (info.width == 0 || info.height == 0 || info.width > 65535 ||
        info.height > 65535 || (info.components != 1 && info.components != 3))
        return Result(Status.unsupported);
    if (cast(ulong)info.width * info.height > limits.maxPixels)
        return Result(Status.limit);
    const nativePlanes = sourcePlanes.length != 0;
    if (nativePlanes && sourcePlanes.length != info.components)
        return Result(Status.invalid);
    const rowBytes = cast(size_t)info.width * info.components;
    if (!nativePlanes)
    {
        if (rowStride < rowBytes || info.height > 1 &&
            rowStride > (size_t.max - rowBytes) / (info.height - 1))
            return Result(Status.invalid);
        if ((cast(size_t)(info.height - 1) * rowStride + rowBytes) > source.length)
            return Result(Status.truncated);
    }
    const size_t hFactor = options.sampling == Sampling.s444 ? 1 : 2;
    const size_t vFactor = options.sampling == Sampling.s420 ? 2 : 1;
    if (nativePlanes)
        foreach (size_t c; 0 .. info.components)
        {
            const scaleH = c == 0 ? 1 : hFactor;
            const scaleV = c == 0 ? 1 : vFactor;
            const planeWidth = (cast(size_t)info.width + scaleH - 1) / scaleH;
            const planeHeight = (cast(size_t)info.height + scaleV - 1) / scaleV;
            if (!planeFits(planeWidth, planeHeight,
                    sourcePlanes[c].rowStride, sourcePlanes[c].bytes.length))
                return Result(Status.truncated);
        }
    const size_t mcuWidth = 8 * hFactor, mcuHeight = 8 * vFactor;
    const mcuCount = ((cast(size_t)info.width + mcuWidth - 1) / mcuWidth) *
        ((cast(size_t)info.height + mcuHeight - 1) / mcuHeight);
    const blocksPerMcu = info.components == 1 ? 1 : hFactor * vFactor + 2;
    if (metadataBytes > size_t.max - 1024 ||
        mcuCount > (size_t.max - 1024 - metadataBytes) / (blocksPerMcu * 512))
        return Result(Status.limit);
    // Research-only diagnostic output. Require complete caller-owned traces
    // before touching any destination so a short trace cannot change results.
    const traceLength = mcuCount * blocksPerMcu * 64;
    if ((sampleTrace.length != 0 && sampleTrace.length < traceLength) ||
        (coefficientTrace.length != 0 && coefficientTrace.length < traceLength))
        return Result(Status.destinationTooSmall);
    const capacity = 1024 + metadataBytes + mcuCount * blocksPerMcu * 512;
    if (capacity > limits.maxFileBytes) return Result(Status.limit);
    if (output.length < capacity) return Result(Status.destinationTooSmall);
    ubyte[64] lumaQuant, chromaQuant;
    quantTable(lumaQuant, lumaBase, options.quality);
    quantTable(chromaQuant, chromaBase, options.quality);
    Huff dc, ac;
    dc.counts[3] = 12;
    foreach (size_t i; 0 .. 12) dc.symbols[i] = cast(ubyte)i;
    if (!build(dc)) return Result(Status.invalid);
    ac.counts[8] = 255; ac.counts[9] = 1;
    foreach (size_t i; 0 .. 256) ac.symbols[i] = cast(ubyte)i;
    if (!build(ac)) return Result(Status.invalid);
    Writer writer;
    writer.bytes = output;
    writer.marker(0xd8);
    writer.marker(0xe0); writer.word(16);
    foreach (value; cast(const(ubyte)[])"JFIF\0") writer.putByte(value);
    writer.putByte(1); writer.putByte(1); writer.putByte(0);
    writer.word(1); writer.word(1); writer.putByte(0); writer.putByte(0);
    if (hasMetadata && options.metadataPolicy == MetadataPolicy.copy)
    {
        if (metadata.exif.length != 0)
        {
            writer.marker(0xe1);
            writer.word(cast(ushort)(2 + metadata.exif.length));
            foreach (value; metadata.exif) writer.putByte(value);
        }
        foreach (size_t segment; 0 .. iccSegments)
        {
            const start = segment * 65519;
            const remaining = metadata.icc.length - start;
            const count = remaining < 65519 ? remaining : 65519;
            writer.marker(0xe2);
            writer.word(cast(ushort)(2 + 14 + count));
            foreach (value; cast(const(ubyte)[])"ICC_PROFILE\0")
                writer.putByte(value);
            writer.putByte(cast(ubyte)(segment + 1));
            writer.putByte(cast(ubyte)iccSegments);
            foreach (value; metadata.icc[start .. start + count])
                writer.putByte(value);
        }
    }
    writer.marker(0xdb); writer.word(67); writer.putByte(0);
    foreach (size_t i; 0 .. 64) writer.putByte(lumaQuant[zig[i]]);
    if (info.components == 3)
    {
        writer.marker(0xdb); writer.word(67); writer.putByte(1);
        foreach (size_t i; 0 .. 64) writer.putByte(chromaQuant[zig[i]]);
    }
    writer.marker(0xc0); writer.word(cast(ushort)(8 + 3 * info.components));
    writer.putByte(8); writer.word(cast(ushort)info.height);
    writer.word(cast(ushort)info.width); writer.putByte(info.components);
    foreach (size_t c; 0 .. info.components)
    {
        writer.putByte(cast(ubyte)(c + 1));
        writer.putByte(c == 0 ? cast(ubyte)((hFactor << 4) | vFactor) : 0x11);
        writer.putByte(c == 0 ? 0 : 1);
    }
    writeHuff(writer, 0, dc); writeHuff(writer, 0x10, ac);
    if (options.restartInterval != 0)
    {
        writer.marker(0xdd); writer.word(4);
        writer.word(options.restartInterval);
    }
    writer.marker(0xda); writer.word(cast(ushort)(6 + 2 * info.components));
    writer.putByte(info.components);
    foreach (size_t c; 0 .. info.components)
    { writer.putByte(cast(ubyte)(c + 1)); writer.putByte(0); }
    writer.putByte(0); writer.putByte(63); writer.putByte(0);
    int[3] predictors;
    size_t mcuIndex;
    size_t blockIndex;
    ubyte restartIndex;
    foreach (size_t my; 0 .. (info.height + mcuHeight - 1) / mcuHeight)
        foreach (size_t mx; 0 .. (info.width + mcuWidth - 1) / mcuWidth)
        {
            foreach (size_t c; 0 .. info.components)
                foreach (size_t by; 0 .. (c == 0 ? vFactor : 1))
                    foreach (size_t bx; 0 .. (c == 0 ? hFactor : 1))
                    {
                        ubyte[64] samples;
                        int[64] coeff;
                        const sampleH = c == 0 ? 1 : hFactor;
                        const sampleV = c == 0 ? 1 : vFactor;
                        foreach (size_t y; 0 .. 8)
                            foreach (size_t x; 0 .. 8)
                            {
                                if (nativePlanes)
                                {
                                    const planeWidth = (cast(size_t)info.width + sampleH - 1) / sampleH;
                                    const planeHeight = (cast(size_t)info.height + sampleV - 1) / sampleV;
                                    const planeX = mx * (c == 0 ? hFactor : 1) * 8 + bx * 8 + x;
                                    const planeY = my * (c == 0 ? vFactor : 1) * 8 + by * 8 + y;
                                    const px = planeX < planeWidth ? planeX : planeWidth - 1;
                                    const py = planeY < planeHeight ? planeY : planeHeight - 1;
                                    samples[y * 8 + x] = sourcePlanes[c].bytes[
                                        py * sourcePlanes[c].rowStride + px];
                                    continue;
                                }
                                version (JpegFloatColorTransform)
                                    double sum = 0;
                                else
                                    long sum = 0;
                                foreach (size_t sy; 0 .. sampleV)
                                    foreach (size_t sx; 0 .. sampleH)
                                    {
                                        const xx = mx * mcuWidth + bx * 8 +
                                            x * sampleH + sx;
                                        const yy = my * mcuHeight + by * 8 +
                                            y * sampleV + sy;
                                        const px = xx < info.width ? xx : info.width - 1;
                                        const py = yy < info.height ? yy : info.height - 1;
                                        const at = py * rowStride + px * info.components;
                                        if (info.components == 1)
                                        {
                                            version (JpegFloatColorTransform)
                                                sum += source[at];
                                            else
                                                sum += cast(long)source[at] * 65536;
                                        }
                                        else
                                        {
                                            version (JpegFloatColorTransform)
                                            {
                                                const r = cast(double)source[at];
                                                const g = cast(double)source[at + 1];
                                                const b = cast(double)source[at + 2];
                                                sum += c == 0 ? 0.299 * r + 0.587 * g + 0.114 * b :
                                                    c == 1 ? 128 - 0.168736 * r - 0.331264 * g + 0.5 * b :
                                                    128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
                                            }
                                            else
                                            {
                                                const r = cast(long)source[at];
                                                const g = cast(long)source[at + 1];
                                                const b = cast(long)source[at + 2];
                                                // Q16 coefficients sum to 65536 for Y and
                                                // zero for centered Cb/Cr. Each pixel is
                                                // accumulated before the subsampling round.
                                                sum += c == 0 ? 19595 * r + 38470 * g + 7471 * b :
                                                    c == 1 ? 128L * 65536 - 11059 * r -
                                                        21709 * g + 32768 * b :
                                                        128L * 65536 + 32768 * r -
                                                        27439 * g - 5329 * b;
                                            }
                                        }
                                    }
                                version (JpegFloatColorTransform)
                                    samples[y * 8 + x] = clamp(sum / (sampleH * sampleV));
                                else
                                {
                                    const denominator = cast(long)(sampleH * sampleV) * 65536;
                                    const rounded = (sum + denominator / 2) / denominator;
                                    samples[y * 8 + x] = cast(ubyte)(rounded < 0 ? 0 :
                                        rounded > 255 ? 255 : rounded);
                                }
                            }
                        if (c == 0) fdct(samples, lumaQuant, coeff);
                        else fdct(samples, chromaQuant, coeff);
                        if (sampleTrace.length != 0)
                            sampleTrace[blockIndex * 64 .. (blockIndex + 1) * 64] = samples[];
                        if (coefficientTrace.length != 0)
                            coefficientTrace[blockIndex * 64 .. (blockIndex + 1) * 64] = coeff[];
                        ++blockIndex;
                        if (!writeBlock(writer, coeff, predictors[c], dc, ac))
                            return Result(Status.invalid);
                    }
            ++mcuIndex;
            if (options.restartInterval != 0 && mcuIndex < mcuCount &&
                mcuIndex % options.restartInterval == 0)
            {
                writer.flushBits();
                writer.marker(cast(ubyte)(0xd0 + restartIndex));
                restartIndex = cast(ubyte)((restartIndex + 1) & 7);
                predictors[] = 0;
            }
        }
    writer.flushBits();
    writer.marker(0xd9);
    return Result(Status.ok, info, writer.pos,
        !hasMetadata ? MetadataDisposition.none :
        options.metadataPolicy == MetadataPolicy.copy ?
            MetadataDisposition.copied : MetadataDisposition.discarded);
}

/// Experimental format-core write: planes already have JFIF Y/Cb/Cr samples
/// (or one gray plane). No colour conversion or chroma resampling occurs.
Result encodeJfifPlanes(Info info, scope const(ConstPlane)[] planes,
    scope ubyte[] output, EncodeOptions options = EncodeOptions.init,
    scope EncodeMetadata metadata = EncodeMetadata.init,
    Limits limits = Limits.init) @safe pure nothrow @nogc
{
    if (planes.length != info.components || planes.length == 0)
        return Result(Status.invalid);
    return encodeJpeg(info, null, 0, output, options, metadata, limits,
        null, null, planes);
}

private struct Component
{
    ubyte id, quant, dc, ac, h, v;
    int predictor;
}

/// Legacy RGB8 oracle convenience. Use decodeJpegPlanes for native components.
/// This bounded slice supports sequential, interleaved 4:4:4/4:2:2/4:2:0 JPEG,
/// including restarts, but not arithmetic coding, CMYK or progressive scans.
Result decodeJpeg(scope const(ubyte)[] file, scope ubyte[] destination,
    size_t rowStride, Limits limits = Limits.init,
    scope MutablePlane[] planes = null) @safe pure nothrow @nogc
{
    const nativePlanes = planes.length != 0;
    if (file.length > limits.maxFileBytes) return Result(Status.limit);
    if (file.length < 4 || file[0] != 0xff || file[1] != 0xd8)
        return Result(Status.invalid);
    ushort[64][4] quant;
    bool[4] quantSeen;
    Huff[4][2] tables; // [class: DC/AC][index]
    Component[3] components;
    ubyte maxH = 1, maxV = 1;
    Info info;
    bool frameSeen, scanSeen, jfifSeen;
    ushort restartInterval;
    int adobeTransform = -1;
    size_t p = 2;
    while (p < file.length)
    {
        if (file[p++] != 0xff) return Result(Status.invalid);
        while (p < file.length && file[p] == 0xff) ++p;
        if (p >= file.length) return Result(Status.truncated);
        const marker = file[p++];
        if (marker == 0xd9) return Result(Status.invalid);
        if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7))
            return Result(Status.unsupported);
        if (file.length - p < 2) return Result(Status.truncated);
        const length = be16(file, p);
        if (length < 2 || length > file.length - p)
            return Result(Status.truncated);
        const end = p + length;
        p += 2;
        if (marker == 0xe0 && p == 6 && end - p >= 5 &&
            file[p .. p + 5] == cast(const(ubyte)[])"JFIF\0")
            jfifSeen = true;
        if (marker == 0xdb) // DQT
        {
            while (p < end)
            {
                const spec = file[p++];
                if ((spec >> 4) != 0 || (spec & 15) >= 4)
                    return Result(Status.unsupported);
                if (end - p < 64) return Result(Status.invalid);
                const id = spec & 15;
                foreach (size_t i; 0 .. 64)
                {
                    const value = file[p++];
                    if (value == 0) return Result(Status.invalid);
                    quant[id][zig[i]] = value;
                }
                quantSeen[id] = true;
            }
        }
        else if (marker == 0xc4) // DHT
        {
            while (p < end)
            {
                if (end - p < 17) return Result(Status.invalid);
                const spec = file[p++];
                if ((spec >> 4) >= 2 || (spec & 15) >= 4)
                    return Result(Status.unsupported);
                auto table = &tables[spec >> 4][spec & 15];
                *table = Huff.init;
                uint count;
                foreach (size_t i; 0 .. 16)
                { table.counts[i] = file[p++]; count += table.counts[i]; }
                if (count > 256 || count > end - p) return Result(Status.invalid);
                foreach (size_t i; 0 .. count) table.symbols[i] = file[p++];
                if (!build(*table)) return Result(Status.invalid);
            }
        }
        else if (marker == 0xc0) // SOF0
        {
            if (frameSeen || end - p < 6 || file[p] != 8)
                return Result(Status.unsupported);
            info.height = be16(file, p + 1);
            info.width = be16(file, p + 3);
            info.components = file[p + 5];
            if (!info.width || !info.height ||
                cast(ulong)info.width * info.height > limits.maxPixels)
                return Result(Status.limit);
            if ((info.components != 1 && info.components != 3) ||
                end - p != 6 + cast(size_t)info.components * 3)
                return Result(Status.unsupported);
            p += 6;
            foreach (size_t i; 0 .. info.components)
            {
                components[i].id = file[p++];
                foreach (size_t j; 0 .. i)
                    if (components[j].id == components[i].id)
                        return Result(Status.invalid);
                const sampling = file[p++];
                components[i].h = sampling >> 4;
                components[i].v = sampling & 15;
                if ((components[i].h != 1 && components[i].h != 2) ||
                    (components[i].v != 1 && components[i].v != 2))
                    return Result(Status.unsupported);
                components[i].quant = file[p++];
                if (components[i].quant >= 4) return Result(Status.unsupported);
            }
            if (info.components == 1 &&
                (components[0].h != 1 || components[0].v != 1))
                return Result(Status.unsupported);
            if (info.components == 3 &&
                (components[1].h != 1 || components[1].v != 1 ||
                 components[2].h != 1 || components[2].v != 1))
                return Result(Status.unsupported);
            maxH = components[0].h;
            maxV = components[0].v;
            // Only 4:4:4, 4:2:2 and 4:2:0 are in this bounded slice.
            if (info.components == 3 && maxH == 1 && maxV == 2)
                return Result(Status.unsupported);
            frameSeen = true;
        }
        else if (marker == 0xdd) // DRI
        {
            if (end - p != 2) return Result(Status.invalid);
            restartInterval = be16(file, p);
        }
        else if (marker == 0xda) // SOS
        {
            if (!frameSeen || scanSeen ||
                (!nativePlanes && info.components == 3 &&
                 (adobeTransform >= 0 && adobeTransform != 1 ||
                  (!jfifSeen && adobeTransform != 1))) ||
                end - p != 1 +
                cast(size_t)info.components * 2 + 3 || file[p++] != info.components)
                return Result(Status.unsupported);
            foreach (size_t i; 0 .. info.components)
            {
                if (file[p++] != components[i].id) return Result(Status.unsupported);
                const selectors = file[p++];
                components[i].dc = selectors >> 4;
                components[i].ac = selectors & 15;
                if (components[i].dc >= 4 || components[i].ac >= 4 ||
                    !tables[0][components[i].dc].valid ||
                    !tables[1][components[i].ac].valid ||
                    !quantSeen[components[i].quant])
                    return Result(Status.invalid);
            }
            if (file[p++] != 0 || file[p++] != 63 || file[p++] != 0)
                return Result(Status.unsupported);
            scanSeen = true;
            const rowBytes = cast(size_t)info.width * info.components;
            size_t planeSamples;
            if (nativePlanes)
            {
                if (planes.length != info.components) return Result(Status.invalid);
                foreach (size_t c; 0 .. info.components)
                {
                    const pw = (cast(size_t)info.width + (c == 0 ? 0 : maxH - 1)) /
                        (c == 0 ? 1 : maxH);
                    const ph = (cast(size_t)info.height + (c == 0 ? 0 : maxV - 1)) /
                        (c == 0 ? 1 : maxV);
                    if (!planeFits(pw, ph, planes[c].rowStride, planes[c].bytes.length))
                        return Result(Status.destinationTooSmall);
                    planeSamples += pw * ph;
                }
            }
            else if (rowStride < rowBytes || info.height > 1 &&
                rowStride > (size_t.max - rowBytes) / (info.height - 1) ||
                (cast(size_t)(info.height - 1) * rowStride + rowBytes) > destination.length)
                return Result(Status.destinationTooSmall);
            // Scan entropy boundaries without assuming EOI immediately after
            // the last byte. Restart markers are validated at MCU boundaries.
            size_t entropyEnd = end;
            while (entropyEnd < file.length)
            {
                if (file[entropyEnd] != 0xff) { ++entropyEnd; continue; }
                if (entropyEnd + 1 >= file.length) return Result(Status.truncated);
                if (file[entropyEnd + 1] == 0x00) { entropyEnd += 2; continue; }
                if (file[entropyEnd + 1] >= 0xd0 &&
                    file[entropyEnd + 1] <= 0xd7)
                { entropyEnd += 2; continue; }
                break;
            }
            if (entropyEnd + 2 != file.length || file[entropyEnd + 1] != 0xd9)
                return Result(Status.unsupported);
            Bits bits;
            bits.data = file[end .. entropyEnd];
            ubyte[256][3] sample;
            const mcuWidth = cast(size_t)maxH * 8;
            const mcuHeight = cast(size_t)maxV * 8;
            const mcuColumns = (info.width + mcuWidth - 1) / mcuWidth;
            const mcuCount = mcuColumns * ((info.height + mcuHeight - 1) / mcuHeight);
            size_t mcuIndex;
            ubyte expectedRestart;
            foreach (size_t my; 0 .. (info.height + mcuHeight - 1) / mcuHeight)
                foreach (size_t mx; 0 .. (info.width + mcuWidth - 1) / mcuWidth)
                {
                    foreach (size_t c; 0 .. info.components)
                    {
                        auto component = &components[c];
                        foreach (size_t by; 0 .. component.v)
                            foreach (size_t bx; 0 .. component.h)
                            {
                                int[64] coeff;
                                ubyte[64] block;
                                const dc = symbol(bits, tables[0][component.dc]);
                                if (dc < 0 || dc > 11) return Result(Status.invalid);
                                const delta = signedValue(bits, cast(uint)dc);
                                if (bits.bad || component.predictor + delta < -2047 ||
                                    component.predictor + delta > 2047)
                                    return Result(Status.invalid);
                                component.predictor += delta;
                                coeff[0] = component.predictor * quant[component.quant][0];
                                size_t k = 1;
                                while (k < 64)
                                {
                                    const code = symbol(bits, tables[1][component.ac]);
                                    if (code < 0) return Result(Status.invalid);
                                    if (code == 0) break;
                                    const run = code >> 4, size = code & 15;
                                    if (size == 0)
                                    {
                                        if (run != 15 || k + 16 > 64)
                                            return Result(Status.invalid);
                                        k += 16;
                                        continue;
                                    }
                                    k += run;
                                    if (k >= 64) return Result(Status.invalid);
                                    if (size > 10) return Result(Status.invalid);
                                    coeff[zig[k]] = signedValue(bits, cast(uint)size) *
                                        quant[component.quant][zig[k]];
                                    ++k;
                                }
                                if (bits.bad) return Result(Status.truncated);
                                idct(coeff, block);
                                foreach (size_t y; 0 .. 8)
                                    foreach (size_t x; 0 .. 8)
                                        sample[c][(by * 8 + y) * 16 + bx * 8 + x] =
                                            block[y * 8 + x];
                            }
                    }
                    if (nativePlanes)
                    {
                        foreach (size_t c; 0 .. info.components)
                        {
                            const pw = c == 0 ? cast(size_t)info.width :
                                (cast(size_t)info.width + maxH - 1) / maxH;
                            const ph = c == 0 ? cast(size_t)info.height :
                                (cast(size_t)info.height + maxV - 1) / maxV;
                            foreach (size_t y; 0 .. cast(size_t)components[c].v * 8)
                                foreach (size_t x; 0 .. cast(size_t)components[c].h * 8)
                                {
                                    const dx = mx * components[c].h * 8 + x;
                                    const dy = my * components[c].v * 8 + y;
                                    if (dx >= pw || dy >= ph) continue;
                                    planes[c].bytes[dy * planes[c].rowStride + dx] =
                                        sample[c][y * 16 + x];
                                }
                        }
                    }
                    else foreach (size_t y; 0 .. mcuHeight)
                        foreach (size_t x; 0 .. mcuWidth)
                        {
                            const dx = mx * mcuWidth + x, dy = my * mcuHeight + y;
                            if (dx >= info.width || dy >= info.height) continue;
                            const dest = dy * rowStride + dx * info.components;
                            if (info.components == 1)
                                destination[dest] = sample[0][y * 16 + x];
                            else if (maxH == 2)
                            {
                                // Stage raw chroma samples in caller storage;
                                // MCU-local interpolation would clamp at every
                                // tile boundary instead of only image edges.
                                destination[dest] = sample[0][y * 16 + x];
                                if (x % 2 == 0 && y % maxV == 0)
                                {
                                    destination[dest + 1] =
                                        sample[1][(y / maxV) * 16 + x / 2];
                                    destination[dest + 2] =
                                        sample[2][(y / maxV) * 16 + x / 2];
                                }
                            }
                            else
                            {
                                const yy = cast(double)sample[0][y * 16 + x];
                                const cb = cast(double)sample[1][y * 16 + x] - 128;
                                const cr = cast(double)sample[2][y * 16 + x] - 128;
                                destination[dest] = clamp(yy + 1.402 * cr);
                                destination[dest + 1] = clamp(yy - 0.344136 * cb - 0.714136 * cr);
                                destination[dest + 2] = clamp(yy + 1.772 * cb);
                            }
                        }
                    ++mcuIndex;
                    if (restartInterval != 0 && mcuIndex < mcuCount &&
                        mcuIndex % restartInterval == 0)
                    {
                        // Encoder pads entropy to the next byte with one bits.
                        if (bits.remaining != 0 &&
                            (bits.buffer & ((1U << bits.remaining) - 1)) !=
                            ((1U << bits.remaining) - 1))
                            return Result(Status.invalid);
                        bits.remaining = 0;
                        if (bits.data.length - bits.pos < 2)
                            return Result(Status.truncated);
                        if (bits.data[bits.pos] != 0xff ||
                            bits.data[bits.pos + 1] != 0xd0 + expectedRestart)
                            return Result(Status.invalid);
                        bits.pos += 2;
                        expectedRestart = cast(ubyte)((expectedRestart + 1) & 7);
                        foreach (ref component; components) component.predictor = 0;
                    }
                }
            if (bits.bad) return Result(Status.truncated);
            if (bits.remaining != 0 &&
                (bits.buffer & ((1U << bits.remaining) - 1)) !=
                ((1U << bits.remaining) - 1))
                return Result(Status.invalid);
            // Any residual full bytes would be an unsupported additional scan.
            if (bits.pos < bits.data.length) return Result(Status.invalid);
            if (!nativePlanes && info.components == 3 && maxH == 2)
                convertSubsampled(destination, info.width, info.height,
                    rowStride, maxV);
            return Result(Status.ok, info, nativePlanes ? planeSamples :
                cast(size_t)info.height * rowBytes);
        }
        else if (marker >= 0xe0 && marker <= 0xef || marker == 0xfe)
        {
            // Adobe APP14 can declare raw RGB rather than YCbCr. Refuse that
            // interpretation rather than silently returning wrong colours.
            if (marker == 0xee && end - p >= 12 &&
                file[p .. p + 5] == "Adobe")
                adobeTransform = file[p + 11];
        }
        else return Result(Status.unsupported);
        p = end;
    }
    return Result(Status.truncated);
}

/// Experimental format-core read into native, subsampled component planes.
/// No YCbCr/RGB conversion, upsampling, ICC or EXIF interpretation occurs.
Result decodeJpegPlanes(scope const(ubyte)[] file, scope MutablePlane[] planes,
    Limits limits = Limits.init) @safe pure nothrow @nogc
{
    if (planes.length != 1 && planes.length != 3)
        return Result(Status.invalid);
    return decodeJpeg(file, null, 0, limits, planes);
}

enum ReadMetadataPolicy : ubyte { reject, report, discard }
enum ReadMetadataDisposition : ubyte { none, reported, discarded }

struct AuditedReadResult
{
    Result pixels;
    FrameResult frame;
    MetadataResult metadata;
    ReadMetadataDisposition metadataDisposition;
    @property bool ok() const @safe pure nothrow @nogc
    { return pixels.ok; }
}

/// Experimental preflight for native-plane decode with metadata-loss policy.
/// EXIF/ICC offsets borrow `file`; other APP/COM payloads and non-default
/// JFIF/Adobe container fields are counted but not preserved.
AuditedReadResult decodeJpegPlanesAudited(scope const(ubyte)[] file,
    scope MutablePlane[] planes, scope MetadataSegment[] iccSegments,
    ReadMetadataPolicy policy = ReadMetadataPolicy.reject,
    Limits limits = Limits.init) @safe pure nothrow @nogc
{
    AuditedReadResult result;
    if (policy > ReadMetadataPolicy.discard)
    {
        result.pixels.status = Status.invalid;
        return result;
    }
    result.frame = inspectJpegFrame(file, limits);
    if (!result.frame.ok)
    {
        result.pixels.status = result.frame.status;
        return result;
    }
    MetadataSegment[255] scratch;
    result.metadata = inspectJpegMetadata(file,
        policy == ReadMetadataPolicy.report ? iccSegments : scratch[], limits);
    if (!result.metadata.ok)
    {
        result.pixels.status = result.metadata.status;
        return result;
    }
    const hasMetadata = result.metadata.exifLength != 0 ||
        result.metadata.iccSegments != 0 || result.metadata.opaqueSegments != 0 ||
        result.metadata.containerLossSegments != 0;
    if (hasMetadata && policy == ReadMetadataPolicy.reject)
    {
        result.pixels.status = Status.unsupported;
        return result;
    }
    result.pixels = decodeJpegPlanes(file, planes, limits);
    if (result.pixels.ok && hasMetadata)
        result.metadataDisposition = policy == ReadMetadataPolicy.report ?
            ReadMetadataDisposition.reported : ReadMetadataDisposition.discarded;
    return result;
}
