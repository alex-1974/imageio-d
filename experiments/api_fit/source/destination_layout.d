module destination_layout;

struct ReadArea
{
    long x;
    long y;
    long width;
    long height;
}

struct BufferLayout
{
    size_t rowStride;
    size_t pixelStride;
    size_t bandStride;
}

struct ImageBuffer
{
    ubyte[] storage;
    BufferLayout layout;
}

struct TechnicalMetadata
{
    uint bandCount;
    uint bitsPerSample;
    bool signedSamples;
    bool floatingPoint;
    bool hasNoData;
    double noData;
    double scale;
    double offset;
}

enum ValueForm { stored, float32 }

struct ReadOptions
{
    ValueForm values;
    uint[] bands;
}

struct ReadResult
{
    ReadArea coverage;
    BufferLayout layout;
    TechnicalMetadata metadata;
    size_t bytesWritten;
}

@safe @nogc nothrow
ReadResult readInto(
    scope ReadArea area,
    scope ReadOptions options,
    ref scope ImageBuffer destination,
    scope TechnicalMetadata metadata
)
{
    assert(options.values == ValueForm.stored);
    assert(options.bands.length != 0);
    assert(destination.storage.length >= destination.layout.rowStride
        * cast(size_t) area.height);

    return ReadResult(
        area,
        destination.layout,
        metadata,
        destination.storage.length
    );
}

@safe @nogc nothrow
void main()
{
    ubyte[4096] storage;
    auto destination = ImageBuffer(
        storage[],
        BufferLayout(256, 2, 1024)
    );
    uint[2] bandsStorage = [1, 3];
    uint[] bands = bandsStorage[];
    auto area = ReadArea(0, 0, 128, 16);
    auto options = ReadOptions(ValueForm.stored, bands);
    auto metadata = TechnicalMetadata(2, 16, false, false, true, 0, 0.01, -100);
    auto result = readInto(area, options, destination, metadata);

    assert(result.coverage == area);
    assert(result.layout == destination.layout);
    assert(result.metadata.noData == 0);
    assert(result.metadata.scale == 0.01);
}
