module api_fit;

import std.stdio : writeln;

struct ReadArea
{
    long x;
    long y;
    long width;
    long height;
}

enum ValueForm { stored, float32 }

struct ImageInfo
{
    long width;
    long height;
    uint bands;
    ValueForm values;
    bool hasNoData;
}

struct ReadOptions
{
    ValueForm values;
    bool preserveTechnicalMetadata;
}

struct ReadResult
{
    ReadArea coverage;
    ValueForm values;
    bool ownsStorage;
}

struct ImageSource
{
    private ImageInfo infoValue;

    static ImageSource fromFile(const(char)[] path) @safe pure nothrow @nogc
    {
        assert(path.length != 0);
        return ImageSource(ImageInfo(4096, 4096, 4, ValueForm.stored, true));
    }
}

struct ImageReader
{
    private ImageInfo _info;

    static ImageReader open(ImageSource source) @safe pure nothrow @nogc
    { return ImageReader(source.infoValue); }

    @property ImageInfo info() const @safe pure nothrow @nogc { return _info; }

    ReadResult read(ReadArea area, ReadOptions options) const @safe pure nothrow @nogc
    {
        return ReadResult(area, options.values, true);
    }
}

@safe void main()
{
    auto reader = ImageReader.open(ImageSource.fromFile("scene.tif"));
    const info = reader.info;
    assert(info.bands == 4 && info.values == ValueForm.stored);

    const area = ReadArea(1024, 2048, 512, 512);
    const decoded = reader.read(area, ReadOptions(ValueForm.stored, true));
    assert(decoded.coverage == area);
    assert(decoded.values == ValueForm.stored);
    assert(decoded.ownsStorage);
    writeln("api-fit probe passed");
}
