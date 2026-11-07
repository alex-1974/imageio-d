module ifd_result;

enum Status { ok, truncated, invalidOrder, invalidMagic, invalidOffset, overflow, unsupported }
enum TiffType : ushort { byteValue = 1, ascii = 2, shortValue = 3, longValue = 4, rational = 5, floatValue = 11 }

struct TagValue
{
    ushort tag;
    ushort type;
    uint count;
    uint valueOffset;
    uint inlineValue;
}

struct ImageTags
{
    uint width;
    uint height;
    uint samplesPerPixel;
    uint bitsPerSample;
    uint bitsPerSampleOffset;
    uint bitsPerSampleCount;
    uint sampleFormat;
    uint compression;
    uint photometric;
    uint predictor;
    uint planarConfiguration;
    uint rowsPerStrip;
    uint tileWidth;
    uint tileLength;
    TagValue noData;
    TagValue modelPixelScale;
    TagValue modelTiepoint;
    TagValue modelTransformation;
    TagValue geoKeyDirectory;
    TagValue geoDoubleParams;
    TagValue geoAsciiParams;
    TagValue stripOffsets;
    TagValue stripByteCounts;
    TagValue tileOffsets;
    TagValue tileByteCounts;
}

struct Result
{
    Status status;
    ImageTags value;
    @property bool ok() const @safe pure nothrow @nogc { return status == Status.ok; }
}

Status validateRepresentation(uint bitsPerSample, uint sampleFormat, uint compression)
    @safe pure nothrow @nogc
{
    if (compression != 1 && compression != 32773) return Status.unsupported;
    if (sampleFormat != 1 && sampleFormat != 3) return Status.unsupported;
    if (bitsPerSample != 8 && bitsPerSample != 16 && bitsPerSample != 32)
        return Status.unsupported;
    return Status.ok;
}

struct Reader
{
    const(ubyte)[] bytes;
    bool little;

    ushort u16(size_t p) const @safe pure nothrow @nogc
    {
        return little ? cast(ushort)(bytes[p] | bytes[p + 1] << 8)
            : cast(ushort)(bytes[p] << 8 | bytes[p + 1]);
    }
    uint u32(size_t p) const @safe pure nothrow @nogc
    {
        return little ? cast(uint)(bytes[p] | bytes[p + 1] << 8 | bytes[p + 2] << 16 | bytes[p + 3] << 24)
            : cast(uint)(bytes[p] << 24 | bytes[p + 1] << 16 | bytes[p + 2] << 8 | bytes[p + 3]);
    }
    bool has(size_t p, size_t n) const @safe pure nothrow @nogc
    { return p <= bytes.length && n <= bytes.length - p; }
}

Result parse(const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    if (bytes.length < 8) return Result(Status.truncated);
    bool little;
    if (bytes[0] == 'I' && bytes[1] == 'I') little = true;
    else if (bytes[0] == 'M' && bytes[1] == 'M') little = false;
    else return Result(Status.invalidOrder);
    auto r = Reader(bytes, little);
    if (r.u16(2) != 42) return Result(Status.invalidMagic);
    auto ifd = r.u32(4);
    if (ifd > bytes.length || !r.has(ifd, 2)) return Result(Status.invalidOffset);
    auto count = r.u16(ifd);
    auto entries = ifd + 2;
    if (count > (size_t.max - entries) / 12 || !r.has(entries, cast(size_t) count * 12 + 4))
        return Result(Status.truncated);

    ImageTags tags;
    foreach (i; 0 .. count)
    {
        auto p = entries + cast(size_t) i * 12;
        TagValue v = TagValue(r.u16(p), r.u16(p + 2), r.u32(p + 4), r.u32(p + 8), r.u32(p + 8));
        if (v.type != TiffType.byteValue && v.type != TiffType.ascii
            && v.type != TiffType.shortValue && v.type != TiffType.longValue
            && v.type != TiffType.rational && v.type != TiffType.floatValue
            && v.type != 12)
            continue;
        if (v.count == 0) return Result(Status.invalidOffset);
        switch (v.tag)
        {
            case 256: tags.width = v.inlineValue; break;
            case 257: tags.height = v.inlineValue; break;
            case 258:
                tags.bitsPerSampleCount = v.count;
                if (v.type == TiffType.shortValue && v.count == 1)
                    tags.bitsPerSample = v.inlineValue & 0xffff;
                else if (v.type == TiffType.shortValue)
                    tags.bitsPerSampleOffset = v.valueOffset;
                else
                    tags.bitsPerSample = v.inlineValue;
                break;
            case 259: tags.compression = v.inlineValue; break;
            case 262: tags.photometric = v.inlineValue; break;
            case 277: tags.samplesPerPixel = v.inlineValue; break;
            case 278: tags.rowsPerStrip = v.inlineValue; break;
            case 284: tags.planarConfiguration = v.inlineValue; break;
            case 317: tags.predictor = v.inlineValue; break;
            case 339: tags.sampleFormat = v.inlineValue; break;
            case 322: tags.tileWidth = v.inlineValue; break;
            case 323: tags.tileLength = v.inlineValue; break;
            case 273: tags.stripOffsets = v; break;
            case 279: tags.stripByteCounts = v; break;
            case 324: tags.tileOffsets = v; break;
            case 325: tags.tileByteCounts = v; break;
            case 33550: tags.modelPixelScale = v; break;
            case 33922: tags.modelTiepoint = v; break;
            case 34264: tags.modelTransformation = v; break;
            case 34735: tags.geoKeyDirectory = v; break;
            case 34736: tags.geoDoubleParams = v; break;
            case 34737: tags.geoAsciiParams = v; break;
            case 42113: tags.noData = v; break;
            default: break;
        }
    }
    if (tags.width == 0 || tags.height == 0 || tags.samplesPerPixel == 0)
        return Result(Status.unsupported);
    if (tags.compression != 0 && tags.compression != 1 && tags.compression != 8
        && tags.compression != 32773)
        return Result(Status.unsupported);
    if (tags.stripOffsets.count != 0 && tags.stripByteCounts.count != tags.stripOffsets.count)
        return Result(Status.invalidOffset);
    if (tags.tileOffsets.count != 0 && tags.tileByteCounts.count != tags.tileOffsets.count)
        return Result(Status.invalidOffset);
    return Result(Status.ok, tags);
}

version (IFDProbe)
@safe @nogc nothrow
void main()
{
    assert(validateRepresentation(8, 1, 1) == Status.ok);
    assert(validateRepresentation(16, 1, 1) == Status.ok);
    assert(validateRepresentation(32, 3, 1) == Status.ok);
    assert(validateRepresentation(24, 1, 1) == Status.unsupported);
    assert(validateRepresentation(16, 2, 1) == Status.unsupported);
    assert(validateRepresentation(16, 1, 5) == Status.unsupported);
}
