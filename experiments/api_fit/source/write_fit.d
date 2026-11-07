module write_fit;

enum ImageFormat { tiff, png, jpeg }
enum ValueForm { stored, float32 }
enum MetadataChoice { keepSupported, dropUnsupported }

struct ImageTarget { ubyte[] storage; }
struct WriteOptions
{
    ImageFormat format;
    ValueForm values;
    MetadataChoice metadata;
    uint quality;
}
struct WriteResult { size_t bytesWritten; bool metadataLoss; bool complete; }

struct ImageWriter
{
    static WriteResult writeFrom(scope const(ubyte)[] pixels,
        scope ImageTarget target, scope WriteOptions options)
        @safe pure nothrow @nogc
    {
        assert(options.values == ValueForm.stored);
        assert(target.storage.length >= pixels.length);
        target.storage[0 .. pixels.length] = pixels[];
        return WriteResult(pixels.length,
            options.metadata == MetadataChoice.dropUnsupported, true);
    }
}

@safe @nogc nothrow
void main()
{
    ubyte[16] pixels;
    ubyte[32] output;
    auto result = ImageWriter.writeFrom(pixels[], ImageTarget(output[]),
        WriteOptions(ImageFormat.tiff, ValueForm.stored,
            MetadataChoice.keepSupported, 0));
    assert(result.complete && result.bytesWritten == pixels.length);
    assert(!result.metadataLoss);
}
