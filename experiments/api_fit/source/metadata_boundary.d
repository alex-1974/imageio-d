module metadata_boundary;

enum SampleKind { unsignedInteger, signedInteger, floatingPoint }

struct TechnicalChannel
{
    uint index;
    const(char)[] name;
    SampleKind sampleKind;
    uint bitsPerSample;
    bool hasNoData;
    double noData;
}

struct TechnicalImageInfo
{
    uint channelCount;
    TechnicalChannel[] channels;
    bool hasColorProfile;
}

// This type belongs to a consumer/imagery layer, not the technical decoder.
enum SemanticRole { unspecified, red, green, blue, alpha, validity }

struct ChannelBinding
{
    uint technicalIndex;
    SemanticRole role;
}

@safe @nogc nothrow pure
bool isTechnicallyNeutral(TechnicalImageInfo info)
{
    // Four channels do not imply RGBA; no semantic role exists here.
    return info.channelCount != 4 || info.channels.length == 4;
}

@safe @nogc nothrow pure
void bindExplicitly(
    scope const(TechnicalImageInfo) info,
    scope const(ChannelBinding)[] bindings
)
{
    foreach (binding; bindings)
        assert(binding.technicalIndex < info.channelCount);
}

@safe @nogc nothrow
void main()
{
    TechnicalChannel[4] channels = [
        TechnicalChannel(0, "B04", SampleKind.unsignedInteger, 16, true, 0),
        TechnicalChannel(1, "B03", SampleKind.unsignedInteger, 16, true, 0),
        TechnicalChannel(2, "B02", SampleKind.unsignedInteger, 16, true, 0),
        TechnicalChannel(3, "B08", SampleKind.unsignedInteger, 16, true, 0)
    ];
    auto info = TechnicalImageInfo(4, channels[], false);
    assert(isTechnicallyNeutral(info));

    ChannelBinding[4] bindings = [
        ChannelBinding(0, SemanticRole.red),
        ChannelBinding(1, SemanticRole.green),
        ChannelBinding(2, SemanticRole.blue),
        ChannelBinding(3, SemanticRole.validity)
    ];
    bindExplicitly(info, bindings[]);
}
