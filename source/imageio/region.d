module imageio.region;

/** An exact rational value used for format-defined sample positions. */
struct Rational
{
    long numerator;
    ulong denominator = 1;

    @property bool valid() const @safe pure nothrow @nogc
    {
        return denominator != 0;
    }
}

/** Return the exact reference-grid position of a stored plane sample.

    `planeIndex` is an index in the returned plane storage. `origin` is the
    plane's integer storage origin and `offset` is the crop phase recorded in
    `ImagePlane.referenceOffsetX/Y`. The result is expressed in reference-grid
    units. This is deliberately a technical coordinate helper; it performs no
    rounding, resampling or colour interpretation.
 */
Rational sampleCenter(size_t origin, size_t planeIndex, uint spacing,
    Rational offset) @safe pure nothrow @nogc
{
    if (!offset.valid || spacing == 0)
        return Rational(0, 0);
    // The public contract uses exact rationals. The bounded decoder paths
    // currently produce offsets whose denominator is the spacing, so this
    // common denominator preserves the value without floating-point loss.
    const auto numerator = cast(long)(origin + planeIndex) * spacing
        * offset.denominator + offset.numerator;
    return Rational(numerator, offset.denominator);
}

/** Position of samples in a plane relative to the region reference grid.

    The reference grid uses full-resolution luma/sample spacing as one unit.
    Factors describe the spacing between samples; offsets describe the first
    sample centre in those same units. Both are technical source facts. No
    resampling is implied.
    An invalid descriptor (zero denominator or factor) represents unavailable
    or conflicting source metadata and must not be interpreted as centred.
 */
struct PlaneSamplingGeometry
{
    uint horizontalFactor = 1;
    uint verticalFactor = 1;
    Rational centerOffsetX;
    Rational centerOffsetY;
    PlaneGeometryStatus status = PlaneGeometryStatus.unavailable;

    @property bool valid() const @safe pure nothrow
    {
        return status == PlaneGeometryStatus.known
            && horizontalFactor != 0 && verticalFactor != 0
            && centerOffsetX.valid && centerOffsetY.valid;
    }

    @property bool known() const @safe pure nothrow { return valid; }
}

/** Machine-readable state of source plane-grid geometry.

    These states are deliberately distinct: a consumer may keep native planes
    for unavailable/unsupported metadata, but must not treat them as centred.
 */
enum PlaneGeometryStatus : ubyte
{
    unavailable,
    known,
    unsupported,
    conflicting,
    invalid
}

/** Construct a descriptor whose spacing is known but whose phase is not. */
PlaneSamplingGeometry unknownPhaseSampling(uint horizontalFactor,
    uint verticalFactor) @safe pure nothrow @nogc
{
    return PlaneSamplingGeometry(horizontalFactor, verticalFactor,
        Rational.init, Rational.init, PlaneGeometryStatus.unavailable);
}

/** Construct a known integer-grid descriptor with a zero phase offset. */
PlaneSamplingGeometry zeroPhaseSampling(uint horizontalFactor,
    uint verticalFactor) @safe pure nothrow @nogc
{
    return PlaneSamplingGeometry(horizontalFactor, verticalFactor,
        Rational(0, 1), Rational(0, 1), PlaneGeometryStatus.known);
}

PlaneSamplingGeometry unsupportedSampling(uint horizontalFactor,
    uint verticalFactor) @safe pure nothrow @nogc
{
    return PlaneSamplingGeometry(horizontalFactor, verticalFactor,
        Rational.init, Rational.init, PlaneGeometryStatus.unsupported);
}

PlaneSamplingGeometry conflictingSampling() @safe pure nothrow @nogc
{
    return PlaneSamplingGeometry(0, 0, Rational.init, Rational.init,
        PlaneGeometryStatus.conflicting);
}

/** Technical JPEG/component description; no colour meaning is implied. */
struct ImagePlaneInfo
{
    uint componentId;
    uint horizontalSampling = 1;
    uint verticalSampling = 1;
    PlaneSamplingGeometry geometry;
    ComponentRole role = ComponentRole.generic;
}

/** Neutral component role reported by a decoder, never a colour conversion. */
enum ComponentRole : ubyte
{
    generic,
    luma,
    chromaBlue,
    chromaRed
}

/** A caller-owned decoded component plane.
    Plane dimensions may differ from the region dimensions, for example for
    subsampled JPEG chroma components. */
struct ImagePlane
{
    ImagePlaneInfo info;
    size_t width;
    size_t height;
    size_t originX;
    size_t originY;
    size_t rowStrideBytes;
    ubyte[] data;
    /** Fractional position of the plane origin relative to the requested
        reference-grid boundary, in reference-grid units. This describes crop
        alignment only; it is not chroma siting and does not make unknown
        source geometry valid. */
    Rational referenceOffsetX;
    Rational referenceOffsetY;
}

/** Copy a visible block into a plane with explicit geometry. */
bool copyPlaneBlock(ref ImagePlane destination, ImagePlane source,
    size_t destinationX, size_t destinationY, size_t width, size_t height)
@safe
{
    if (destinationX > destination.width || destinationY > destination.height
        || width > destination.width - destinationX
        || height > destination.height - destinationY
        || width > source.width || height > source.height
        || destination.rowStrideBytes < destination.width
        || source.rowStrideBytes < source.width)
        return false;
    if (destination.height != 0 && destination.rowStrideBytes > size_t.max / destination.height)
        return false;
    if (source.height != 0 && source.rowStrideBytes > size_t.max / source.height)
        return false;
    if (destination.data.length < destination.rowStrideBytes * destination.height
        || source.data.length < source.rowStrideBytes * source.height)
        return false;
    foreach (row; 0 .. height)
        destination.data[(destinationY + row) * destination.rowStrideBytes + destinationX
            .. (destinationY + row) * destination.rowStrideBytes + destinationX + width] =
            source.data[row * source.rowStrideBytes .. row * source.rowStrideBytes + width];
    return true;
}

/** Caller-owned collection used while assembling native component blocks. */
struct PlaneAccumulator
{
    ImagePlane[] planes;

    @property bool valid() const @safe pure nothrow
    {
        return planes.length != 0;
    }

    bool append(size_t component, ImagePlane block, size_t x, size_t y,
        size_t width, size_t height)
    @safe
    {
        if (component >= planes.length)
            return false;
        return copyPlaneBlock(planes[component], block, x, y, width, height);
    }
}

/** A two-dimensional decoded image region. */
struct ImageRegion
{
    ImageRegionInfo info;
    size_t originX;
    size_t originY;
    ubyte[] data;
    ImagePlane[] planes;
}

/** Technical description of decoded image samples. */
struct ImageRegionInfo
{
    size_t width;
    size_t height;
    size_t componentCount;
    SampleFormat sampleFormat;
    PixelLayout layout;
    size_t rowStrideBytes = 0;
    size_t sampleStrideBytes = 0;
    size_t planeStrideBytes = 0;
    SourceModel sourceModel = SourceModel.unknown;
    SourceColorMetadata colorMetadata;
}

/** Neutral source signalling discovered in encoded metadata. */
enum SourceModel : ubyte
{
    unknown,
    gray,
    yCbCr,
    rgb
}

/** Neutral colour-source facts. Unknown means the encoded source did not
    declare the value; it never authorizes a decoder-side guess. */
struct SourceColorMetadata
{
    MetadataState state = MetadataState.absent;
    SourceModel model = SourceModel.unknown;
    MetadataState modelState = MetadataState.absent;
    ColorMatrix matrix = ColorMatrix.unknown;
    MetadataState matrixState = MetadataState.absent;
    ColorRange range = ColorRange.unknown;
    MetadataState rangeState = MetadataState.absent;
    TransferFunction transfer = TransferFunction.unknown;
    MetadataState transferState = MetadataState.absent;
    ColorPrimaries primaries = ColorPrimaries.unknown;
    MetadataState primariesState = MetadataState.absent;
    uint bitDepth;
    MetadataState bitDepthState = MetadataState.absent;
    SampleSignedness signedness = SampleSignedness.unknown;
    ByteOrder byteOrder = ByteOrder.unknown;
}

enum MetadataState : ubyte { absent, known, unsupported, conflicting }
enum ColorRange : ubyte { unknown, full, video }
enum TransferFunction : ubyte { unknown, linear, sRGB }
enum ColorPrimaries : ubyte { unknown, bt601, bt709 }
enum ColorMatrix : ubyte { unknown, bt601, bt709, identity }
enum SampleSignedness : ubyte { unknown, unsigned, signed }
enum ByteOrder : ubyte { unknown, littleEndian, bigEndian }

enum SampleFormat : ubyte
{
    u8,
    u16,
    f32,
    f64
}

enum PixelLayout : ubyte
{
    interleaved,
    planar
}

unittest
{
    auto luma = new ubyte[](16 * 8);
    auto chroma = new ubyte[](8 * 4);
    ImagePlane[] planes = [
        ImagePlane(ImagePlaneInfo(1, 1, 1), 16, 8, 0, 0, 16, luma),
        ImagePlane(ImagePlaneInfo(2, 2, 2), 8, 4, 0, 0, 8, chroma)
    ];
    assert(planes[0].width == 16 && planes[1].height == 4);
    auto destination = ImagePlane(ImagePlaneInfo(1), 4, 3, 0, 0, 4,
        new ubyte[](12));
    auto block = ImagePlane(ImagePlaneInfo(1), 2, 2, 0, 0, 2,
        [ubyte(1), 2, 3, 4]);
    assert(copyPlaneBlock(destination, block, 1, 1, 2, 2));
    assert(destination.data == [ubyte(0), 0, 0, 0, 0, 1, 2, 0,
        0, 3, 4, 0]);
    PlaneAccumulator accumulator = PlaneAccumulator([destination]);
    assert(accumulator.valid);
    assert(accumulator.append(0, block, 0, 0, 2, 2));

    auto geometry = PlaneSamplingGeometry(2, 2, Rational(1, 2), Rational(1, 2),
        PlaneGeometryStatus.known);
    assert(geometry.valid);
    assert(geometry.centerOffsetX.numerator == 1
        && geometry.centerOffsetX.denominator == 2);
    assert(!PlaneSamplingGeometry(2, 2, Rational(1, 0), Rational(1, 2),
        PlaneGeometryStatus.known).valid);

    // JPEG-like 4:2:0 and 4:2:2 descriptors retain sampling factors while
    // leaving phase unknown when the source did not declare it.
    auto jpeg420 = ImagePlaneInfo(2, 2, 2);
    assert(jpeg420.horizontalSampling == 2 && jpeg420.verticalSampling == 2);
    assert(!jpeg420.geometry.valid);
    auto jpeg422 = ImagePlaneInfo(2, 2, 1);
    assert(jpeg422.horizontalSampling == 2 && jpeg422.verticalSampling == 1);
    assert(!jpeg422.geometry.valid);
    auto unknown = unknownPhaseSampling(2, 2);
    assert(unknown.horizontalFactor == 2 && !unknown.valid);

    auto known = zeroPhaseSampling(2, 2);
    assert(known.valid && known.centerOffsetX.numerator == 0);
    assert(known.status == PlaneGeometryStatus.known);
    assert(unknown.status == PlaneGeometryStatus.unavailable);
    assert(unsupportedSampling(2, 2).status == PlaneGeometryStatus.unsupported);
    assert(conflictingSampling().status == PlaneGeometryStatus.conflicting);

    // A cropped, padded destination retains technical metadata while blocks
    // are assembled at a non-zero destination offset.
    auto cropInfo = ImagePlaneInfo(2, 1, 1,
        unknownPhaseSampling(2, 1), ComponentRole.chromaBlue);
    auto cropped = ImagePlane(cropInfo, 5, 3, 7, 9, 8,
        new ubyte[](24));
    auto block2 = ImagePlane(cropInfo, 2, 2, 7, 9, 4,
        [ubyte(10), 11, 0, 0, 12, 13, 0, 0]);
    assert(copyPlaneBlock(cropped, block2, 1, 1, 2, 2));
    assert(cropped.info.role == ComponentRole.chromaBlue);
    assert(cropped.info.geometry.horizontalFactor == 2);
    assert(cropped.originX == 7 && cropped.originY == 9);
    assert(cropped.data[1 * cropped.rowStrideBytes + 1 .. 1 * cropped.rowStrideBytes + 3]
        == [ubyte(10), 11]);
    assert(cropped.data[2 * cropped.rowStrideBytes + 1 .. 2 * cropped.rowStrideBytes + 3]
        == [ubyte(12), 13]);

    auto center = sampleCenter(0, 0, 2, Rational(1, 2));
    assert(center == Rational(1, 2));
    center = sampleCenter(0, 1, 2, Rational(1, 2));
    assert(center == Rational(5, 2));
    assert(!sampleCenter(0, 0, 0, Rational(0, 1)).valid);
}
