/**
 * Bounded TIFF inspection, planning and research decoder entry points.
 *
 * The implemented subset is intentionally explicit and incomplete. Callers
 * must inspect the returned error/capability state before using decoded data;
 * no implicit colour or geospatial semantics are applied.
 */
module imageio.tiff;

import transport : ByteRange, ByteSource, ReadError, ReadLimits, ReadResult;
import imageio.region : ImageRegion, ImageRegionInfo, ImagePlane, ImagePlaneInfo,
    PixelLayout, SampleFormat, ComponentRole, SourceModel, MetadataState,
    SampleSignedness, SourceColorMetadata, ColorMatrix, ColorRange,
    TransferFunction, ColorPrimaries, ByteOrder,
    Rational, unknownPhaseSampling, sampleCenter;
import compression.deflate : InflateWorkspace;
import compression.zlib : inflateZlib;
import compression.packbits : decodePackBits;
import compression.lzw : LzwWorkspace, decodeLzw;
import compression.jpeg : decodeJpeg, decodeJpegPlanes, inspectJpegFrame,
    encodeJpeg, Info, EncodeOptions, Sampling, MutablePlane, Limits,
    ComponentSignal, PixelRegion, RoiPlan, RoiDecodeReport, RestartIndexEntry,
    buildJpegRestartIndex, planJpegPlanesRegion,
    decodeJpegPlanesRegion, decodeJpegPlanesRegionIndexed,
    inspectJpegColorMetadata, MetadataSegment, JpegColorMetadata,
    CompressionByteOrder = ByteOrder;
import compression.core : DecodeStatus;

/** Minimal technical TIFF header information available without decoding pixels. */
struct TiffHeader
{
    bool littleEndian;
    ushort tiffVersion;
    ulong firstIfdOffset;
    bool bigTiff;
}

private SourceColorMetadata mapJpegColorMetadata(
    JpegColorMetadata source) @safe pure nothrow @nogc
{
    SourceColorMetadata result;
    result.state = cast(MetadataState) source.state;
    result.model = cast(SourceModel) source.model;
    result.modelState = cast(MetadataState) source.modelState;
    result.matrix = cast(ColorMatrix) source.matrix;
    result.matrixState = cast(MetadataState) source.matrixState;
    result.range = cast(ColorRange) source.range;
    result.rangeState = cast(MetadataState) source.rangeState;
    result.transfer = cast(TransferFunction) source.transfer;
    result.transferState = cast(MetadataState) source.transferState;
    result.primaries = cast(ColorPrimaries) source.primaries;
    result.primariesState = cast(MetadataState) source.primariesState;
    result.bitDepth = source.bitDepth;
    result.bitDepthState = cast(MetadataState) source.bitDepthState;
    result.signedness = cast(SampleSignedness) source.signedness;
    result.byteOrder = source.byteOrder == CompressionByteOrder.notApplicable
        ? ByteOrder.unknown : cast(ByteOrder) source.byteOrder;
    return result;
}

private struct TiffTagReference
{
    ushort type;
    ulong count;
    ulong valueOffset;
}

struct TiffImageInfo
{
    TiffHeader header;
    uint width;
    uint height;
    uint samplesPerPixel = 1;
    uint bitsPerSample;
    private TiffTagReference bitsPerSampleValues;
    uint compression = 1;
    uint photometric;
    uint predictor;
    uint planarConfiguration = 1;
    uint rowsPerStrip;
    uint tileWidth;
    uint tileLength;
    uint tileCount;
    ushort tileOffsetType;
    ushort tileByteCountType;
    /** Technical GeoTIFF presence/count facts; values are not CRS objects. */
    ulong geoKeyDirectoryCount;
    /** Raw GeoKeyDirectoryTag values, grouped as key-directory entries. */
    ushort[] geoKeyDirectoryValues;
    ushort modelTypeGeoKey;
    ushort rasterTypeGeoKey;
    ushort geographicCrsGeoKey;
    ushort projectedCrsGeoKey;
    bool hasModelTypeGeoKey;
    bool hasRasterTypeGeoKey;
    bool hasGeographicCrsGeoKey;
    bool hasProjectedCrsGeoKey;
    ulong modelPixelScaleCount;
    ulong modelTiepointCount;
    ulong modelTransformationCount;
    ulong noDataCount;
    /** Raw ASCII/byte payload of GDAL_NODATA, including any terminator. */
    ubyte[] noDataValue;
    /** Validated raw technical GeoTIFF values, in tag order. */
    double[] modelPixelScale;
    double[] modelTiepoint;
    double[] modelTransformation;
    private TiffTagReference stripOffsets;
    private TiffTagReference stripByteCounts;
    private TiffTagReference tileOffsets;
    private TiffTagReference tileByteCounts;
    private TiffTagReference geoKeyDirectoryRef;
    private TiffTagReference modelPixelScaleValues;
    private TiffTagReference modelTiepointValues;
    private TiffTagReference modelTransformationValues;
    private TiffTagReference noData;
    private TiffTagReference jpegTables;
    ulong nextIfdOffset;

    /** Look up a SHORT GeoKey value from GeoKeyDirectoryTag.

        Only inline SHORT values are returned. Keys stored in another TIFF
        tag remain available through the raw directory and are intentionally
        not silently coerced into a CRS or string value.
     */
    bool geoKeyShort(ushort keyId, out ushort value) const @safe pure nothrow @nogc
    {
        value = 0;
        if (geoKeyDirectoryValues.length < 4
            || geoKeyDirectoryValues[3] == 0)
            return false;
        const keyCount = geoKeyDirectoryValues[3];
        if (geoKeyDirectoryValues.length < 4 + keyCount * 4)
            return false;
        foreach (i; 0 .. keyCount)
        {
            const p = 4 + i * 4;
            if (geoKeyDirectoryValues[p] == keyId)
            {
                if (geoKeyDirectoryValues[p + 1] != 0
                    || geoKeyDirectoryValues[p + 2] != 1)
                    return false;
                value = geoKeyDirectoryValues[p + 3];
                return true;
            }
        }
        return false;
    }
}

enum TiffInspectionError : ubyte
{
    none,
    sourceFailure,
    invalidRange,
    truncated,
    invalidByteOrder,
    invalidMagic,
    unsupportedVersion
}

enum ImageFormat : ubyte
{
    unknown,
    tiff
}

struct FormatDetectionResult
{
    ImageFormat format;
    TiffInspectionError error;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffInspectionError.none;
    }
}

struct TiffInspectionResult
{
    TiffInspectionError error;
    TiffHeader header;
    TiffImageInfo info;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffInspectionError.none;
    }
}

enum TiffDecodeError : ubyte
{
    none,
    unsupportedFormat,
    invalidRegion,
    unsupportedLayout,
    sourceFailure,
    truncated
}

/** Result of a bounded TIFF ROI decode.

    `bytesRequested` describes encoded source bytes planned for the selected
    strips or tiles. `decodedBytes` is the native result size, and
    `fromNativeBlocks` identifies strip/tile traversal rather than an implicit
    full-image fallback. `levelIndex` and `usedOverview` identify the IFD
    level selected by the caller.
 */
struct TiffDecodeResult
{
    TiffDecodeError error;
    ImageRegion region;
    /** Technical source inspection for the level that produced `region`. */
    TiffImageInfo sourceInfo;
    /** Selected IFD level; level zero is the base image. */
    size_t levelIndex;
    /** True when the caller requested best-level selection and an overview
        level was selected instead of the base level. */
    bool usedOverview;
    /** Encoded source bytes requested for the decoded region. */
    ulong bytesRequested;
    /** Native decoded bytes materialized into the result. */
    ulong decodedBytes;
    /** True when the result was produced by strip/tile-native traversal. */
    bool fromNativeBlocks;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffDecodeError.none;
    }
}

struct TiffRegionPlan
{
    TiffImageInfo info;
    size_t levelIndex;
    size_t requestedX;
    size_t requestedY;
    size_t requestedWidth;
    size_t requestedHeight;
    size_t blockCount;
    ulong encodedBytes;
    ulong decodedBytes;

    @property double amplification() const @safe pure nothrow @nogc
    {
        return encodedBytes == 0 ? 0.0
            : cast(double) decodedBytes / cast(double) encodedBytes;
    }
}

struct TiffPlanResult
{
    TiffDecodeError error;
    TiffRegionPlan plan;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffDecodeError.none;
    }
}

struct TiffLevelInfo
{
    ulong ifdOffset;
    uint width;
    uint height;
    ulong nextIfdOffset;
}

struct TiffLevelsResult
{
    TiffDecodeError error;
    TiffLevelInfo[] levels;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffDecodeError.none;
    }
}

struct TiffLevelSelection
{
    size_t levelIndex;
    TiffLevelInfo level;
}

struct TiffSelectionResult
{
    TiffDecodeError error;
    TiffLevelSelection selection;

    @property bool ok() const @safe pure nothrow @nogc
    {
        return error == TiffDecodeError.none;
    }
}

/** Decode a baseline JPEG byte range into native component planes.
    No YCbCr/RGB conversion or chroma upsampling is performed. */
TiffDecodeResult decodeJpegPlanes(scope const(ubyte)[] encoded)
@safe
{
    auto frame = inspectJpegFrame(encoded[]);
    if (!frame.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);
    MetadataSegment[255] metadataSegments;
    auto colorMetadata = inspectJpegColorMetadata(encoded[], metadataSegments[]);
    if (!colorMetadata.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);
    auto width = cast(size_t) frame.info.width;
    auto height = cast(size_t) frame.info.height;
    auto maxH = frame.horizontal[0];
    auto maxV = frame.vertical[0];
    foreach (c; 1 .. frame.info.components)
    {
        if (frame.horizontal[c] > maxH) maxH = frame.horizontal[c];
        if (frame.vertical[c] > maxV) maxV = frame.vertical[c];
    }
    ImagePlane[] planes = new ImagePlane[](frame.info.components);
    MutablePlane[] destinations = new MutablePlane[](frame.info.components);
    foreach (c; 0 .. frame.info.components)
    {
        auto planeWidth = (width * frame.horizontal[c] + maxH - 1) / maxH;
        auto planeHeight = (height * frame.vertical[c] + maxV - 1) / maxV;
        auto bytes = new ubyte[](planeWidth * planeHeight);
        auto role = ComponentRole.generic;
        if (frame.signal == ComponentSignal.jfifYCbCr
            || frame.signal == ComponentSignal.adobeYCbCr)
            role = c == 0 ? ComponentRole.luma
                : c == 1 ? ComponentRole.chromaBlue : ComponentRole.chromaRed;
        auto planeInfo = ImagePlaneInfo(frame.ids[c], frame.horizontal[c],
            frame.vertical[c],
            unknownPhaseSampling(maxH / frame.horizontal[c],
                maxV / frame.vertical[c]), role);
        planes[c] = ImagePlane(planeInfo, planeWidth, planeHeight, 0, 0,
            planeWidth, bytes);
        destinations[c] = MutablePlane(planes[c].data, planeWidth);
    }
    auto decoded = decodeJpegPlanes(encoded[], destinations[]);
    if (!decoded.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);
    auto info = ImageRegionInfo(width, height, frame.info.components,
        SampleFormat.u8, PixelLayout.planar, 0, 0, 0,
        frame.signal == ComponentSignal.jfifYCbCr
            || frame.signal == ComponentSignal.adobeYCbCr
            ? SourceModel.yCbCr
            : frame.signal == ComponentSignal.adobeRGB ? SourceModel.rgb
            : frame.signal == ComponentSignal.gray ? SourceModel.gray
            : SourceModel.unknown);
    info.colorMetadata = mapJpegColorMetadata(colorMetadata.color);
    info.sourceModel = info.colorMetadata.model;
    return TiffDecodeResult(TiffDecodeError.none,
        ImageRegion(info, 0, 0, null, planes));
}

/** Decode a JPEG ROI through the bounded fallback path.

    The current baseline codec decodes complete component planes, then crops
    the requested reference-grid window. `region.originX/Y` identify the
    requested source window and each plane origin identifies the corresponding
    source-plane coordinate. This is intentionally observable full-decode
    behaviour; native MCU skipping is a later JPEG gate qualification.
 */
TiffDecodeResult decodeJpegRegion(scope const(ubyte)[] encoded,
    size_t x, size_t y, size_t width, size_t height)
@safe
{
    auto frame = inspectJpegFrame(encoded[]);
    if (!frame.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);
    MetadataSegment[255] metadataSegments;
    auto colorMetadata = inspectJpegColorMetadata(encoded[], metadataSegments[]);
    if (!colorMetadata.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);
    auto plan = planJpegPlanesRegion(frame,
        PixelRegion(x, y, width, height));
    if (!plan.ok)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);

    ImagePlane[] planes = new ImagePlane[](frame.info.components);
    MutablePlane[] destinations = new MutablePlane[](frame.info.components);
    foreach (c; 0 .. frame.info.components)
    {
        auto maxH = frame.horizontal[0];
        auto maxV = frame.vertical[0];
        // Convert the component's sampling factor to its spacing in the
        // reference grid.  The luma component is normally maxH/maxV and thus
        // has spacing one; a 1x1 chroma component in a 4:2:0 frame has spacing
        // two.  Keeping this as an integer ratio preserves odd-crop phase.
        const h = maxH / frame.horizontal[c];
        const v = maxV / frame.vertical[c];
        const planeX = x / h;
        const planeY = y / v;
        const planeWidth = (width + h - 1) / h;
        const planeHeight = (height + v - 1) / v;
        auto bytes = new ubyte[](planeWidth * planeHeight);
        auto role = ComponentRole.generic;
        if (frame.signal == ComponentSignal.jfifYCbCr
            || frame.signal == ComponentSignal.adobeYCbCr)
            role = c == 0 ? ComponentRole.luma
                : c == 1 ? ComponentRole.chromaBlue : ComponentRole.chromaRed;
        auto info = ImagePlaneInfo(frame.ids[c], frame.horizontal[c],
            frame.vertical[c], unknownPhaseSampling(
                maxH / frame.horizontal[c], maxV / frame.vertical[c]), role);
        planes[c] = ImagePlane(info, planeWidth, planeHeight,
            planeX, planeY, planeWidth, bytes,
            Rational(cast(long)(x % h), h),
            Rational(cast(long)(y % v), v));
        destinations[c] = MutablePlane(bytes, planeWidth);
    }

    const pixelCount = cast(ulong) frame.info.width * frame.info.height;
    const mcuCount = ((frame.info.width + frame.horizontal[0] * 8 - 1)
        / (frame.horizontal[0] * 8))
        * ((frame.info.height + frame.vertical[0] * 8 - 1)
        / (frame.vertical[0] * 8));
    RestartIndexEntry[] entries = new RestartIndexEntry[](cast(size_t)mcuCount);
    auto index = buildJpegRestartIndex(encoded[], entries[]);
    auto decoded = index.ok && index.entries != 0
        ? decodeJpegPlanesRegionIndexed(encoded[], PixelRegion(x, y, width, height),
            destinations[], index, entries[], null)
        : decodeJpegPlanesRegion(encoded[], PixelRegion(x, y, width, height),
            destinations[], null);
    if (!decoded.ok)
        return TiffDecodeResult(TiffDecodeError.truncated);

    auto model = frame.signal == ComponentSignal.jfifYCbCr
        || frame.signal == ComponentSignal.adobeYCbCr ? SourceModel.yCbCr
        : frame.signal == ComponentSignal.adobeRGB ? SourceModel.rgb
        : frame.signal == ComponentSignal.gray ? SourceModel.gray
        : SourceModel.unknown;
    auto regionInfo = ImageRegionInfo(width, height, frame.info.components,
        SampleFormat.u8, PixelLayout.planar, 0, 0, 0, model);
    regionInfo.colorMetadata = mapJpegColorMetadata(colorMetadata.color);
    regionInfo.sourceModel = regionInfo.colorMetadata.model;
    return TiffDecodeResult(TiffDecodeError.none,
        ImageRegion(regionInfo, x, y, null, planes));
}

/**
 * Reads the fixed TIFF header through the general transport contract.
 *
 * This is deliberately limited to technical container inspection. IFD
 * parsing, tile selection, decompression and decoded image regions are
 * separate format-gate work and do not belong in this first transport-backed
 * boundary implementation.
 */
TiffInspectionResult inspectHeader(ByteSource source)
@safe
{
    ubyte[16] bytes;
    auto result = source.read(ByteRange(0, 8), bytes[0 .. 8], ReadLimits(8));
    if (result.hasError)
        return TiffInspectionResult(result.error().kind == ReadError.invalidRange
            ? TiffInspectionError.truncated : mapError(result.error().kind));

    if (bytes[0] == 'I' && bytes[1] == 'I')
    {
        auto tiffVersion = cast(ushort)(bytes[2] | (bytes[3] << 8));
        if (tiffVersion == 43)
        {
            auto extended = source.read(ByteRange(8, 8), bytes[8 .. 16], ReadLimits(8));
            if (extended.hasError)
                return TiffInspectionResult(extended.error().kind == ReadError.invalidRange
                    ? TiffInspectionError.truncated : mapError(extended.error().kind));
            if (read16(bytes[4 .. 6], true) != 8 || read16(bytes[6 .. 8], true) != 0)
                return TiffInspectionResult(TiffInspectionError.invalidMagic);
            return validateHeader(true, tiffVersion, read64(bytes[8 .. 16], true), true);
        }
        auto offset = cast(ulong)(bytes[4] | (bytes[5] << 8)
            | (bytes[6] << 16) | (bytes[7] << 24));
        return validateHeader(true, tiffVersion, offset, false);
    }
    if (bytes[0] == 'M' && bytes[1] == 'M')
    {
        auto tiffVersion = cast(ushort)((bytes[2] << 8) | bytes[3]);
        if (tiffVersion == 43)
        {
            auto extended = source.read(ByteRange(8, 8), bytes[8 .. 16], ReadLimits(8));
            if (extended.hasError)
                return TiffInspectionResult(extended.error().kind == ReadError.invalidRange
                    ? TiffInspectionError.truncated : mapError(extended.error().kind));
            if (read16(bytes[4 .. 6], false) != 8 || read16(bytes[6 .. 8], false) != 0)
                return TiffInspectionResult(TiffInspectionError.invalidMagic);
            return validateHeader(false, tiffVersion, read64(bytes[8 .. 16], false), true);
        }
        auto offset = cast(ulong)((bytes[4] << 24) | (bytes[5] << 16)
            | (bytes[6] << 8) | bytes[7]);
        return validateHeader(false, tiffVersion, offset, false);
    }
    return TiffInspectionResult(TiffInspectionError.invalidByteOrder);
}

/** Detect the image container from its signature, not its file extension. */
FormatDetectionResult detectFormat(ByteSource source)
@safe
{
    auto header = inspectHeader(source);
    if (header.ok)
        return FormatDetectionResult(ImageFormat.tiff, TiffInspectionError.none);
    if (header.error == TiffInspectionError.invalidByteOrder
        || header.error == TiffInspectionError.invalidMagic)
        return FormatDetectionResult(ImageFormat.unknown, TiffInspectionError.none);
    return FormatDetectionResult(ImageFormat.unknown, header.error);
}

/** Read and validate the first classic-TIFF IFD using bounded range reads. */
TiffInspectionResult inspect(ByteSource source)
@safe
{
    auto headerResult = inspectHeader(source);
    if (!headerResult.ok)
        return TiffInspectionResult(headerResult.error);
    return inspectIfd(source, headerResult.header,
        headerResult.header.firstIfdOffset);
}

private TiffInspectionResult inspectIfd(ByteSource source, TiffHeader header,
    ulong ifdOffset)
@safe
{
    if (header.bigTiff)
        return inspectBigIfd(source, header, ifdOffset);
    ubyte[2] countBytes;
    auto countResult = source.read(ByteRange(ifdOffset, 2), countBytes[], ReadLimits(2));
    if (countResult.hasError)
        return TiffInspectionResult(countResult.error().kind == ReadError.invalidRange
            ? TiffInspectionError.truncated : mapError(countResult.error().kind));

    auto count = read16(countBytes[], header.littleEndian);
    if (count > (size_t.max - 6) / 12)
        return TiffInspectionResult(TiffInspectionError.invalidRange);

    auto length = 2 + cast(size_t) count * 12 + 4;
    auto offset = cast(ulong) ifdOffset;
    ubyte[] ifd = new ubyte[](length);
    auto ifdResult = source.read(ByteRange(offset, length), ifd[], ReadLimits(length));
    if (ifdResult.hasError)
        return TiffInspectionResult(ifdResult.error().kind == ReadError.invalidRange
            ? TiffInspectionError.truncated : mapError(ifdResult.error().kind));

    TiffImageInfo info;
    info.header = header;
    foreach (i; 0 .. count)
    {
        auto p = 2 + cast(size_t) i * 12;
        auto tag = read16(ifd[p .. p + 2], info.header.littleEndian);
        auto type = read16(ifd[p + 2 .. p + 4], info.header.littleEndian);
        auto elements = read32(ifd[p + 4 .. p + 8], info.header.littleEndian);
        auto value = read32(ifd[p + 8 .. p + 12], info.header.littleEndian);
        auto reference = TiffTagReference(type, elements, value);
        auto scalar = scalarValue(type, elements, value, info.header.littleEndian);
        switch (tag)
        {
            case 256: info.width = scalar; break;
            case 257: info.height = scalar; break;
            case 258:
                info.bitsPerSample = scalar;
                info.bitsPerSampleValues = reference;
                break;
            case 259: info.compression = scalar; break;
            case 262: info.photometric = scalar; break;
            case 277: info.samplesPerPixel = scalar; break;
            case 278: info.rowsPerStrip = scalar; break;
            case 284: info.planarConfiguration = scalar; break;
            case 317: info.predictor = scalar; break;
            case 322: info.tileWidth = scalar; break;
            case 323: info.tileLength = scalar; break;
            case 273: info.stripOffsets = reference; break;
            case 279: info.stripByteCounts = reference; break;
            case 324:
                info.tileOffsets = reference;
                info.tileCount = elements;
                info.tileOffsetType = type;
                break;
            case 325:
                info.tileByteCounts = reference;
                info.tileByteCountType = type;
                break;
            case 33550: info.modelPixelScaleCount = elements; info.modelPixelScaleValues = reference; break;
            case 33922: info.modelTiepointCount = elements; info.modelTiepointValues = reference; break;
            case 34264: info.modelTransformationCount = elements; info.modelTransformationValues = reference; break;
            case 34735: info.geoKeyDirectoryRef = reference; info.geoKeyDirectoryCount = elements; break;
            case 42113: info.noData = reference; info.noDataCount = elements; break;
            case 347: info.jpegTables = reference; break;
            default: break;
        }
    }
    auto nextOffsetPosition = 2 + cast(size_t) count * 12;
    info.nextIfdOffset = read32(
        ifd[nextOffsetPosition .. nextOffsetPosition + 4],
        info.header.littleEndian);
    if (info.width == 0 || info.height == 0 || info.samplesPerPixel == 0)
        return TiffInspectionResult(TiffInspectionError.invalidMagic);
    if (info.bitsPerSample != 0 && info.bitsPerSample != 8
        && info.bitsPerSample != 16 && info.bitsPerSample != 32)
        return TiffInspectionResult(TiffInspectionError.unsupportedVersion);
    if (!populateGeoTechnical(source, info))
        return TiffInspectionResult(TiffInspectionError.truncated);
    return TiffInspectionResult(TiffInspectionError.none, info.header, info);
}

private TiffInspectionResult inspectBigIfd(ByteSource source, TiffHeader header,
    ulong ifdOffset)
@safe
{
    ubyte[8] countBytes;
    auto countResult = source.read(ByteRange(ifdOffset, 8), countBytes[], ReadLimits(8));
    if (countResult.hasError)
        return TiffInspectionResult(countResult.error().kind == ReadError.invalidRange
            ? TiffInspectionError.truncated : mapError(countResult.error().kind));
    auto count = read64(countBytes[], header.littleEndian);
    if (count > (size_t.max - 16) / 20)
        return TiffInspectionResult(TiffInspectionError.invalidRange);
    auto length = 8 + cast(size_t) count * 20 + 8;
    ubyte[] ifd = new ubyte[](length);
    auto ifdResult = source.read(ByteRange(ifdOffset, length), ifd[], ReadLimits(length));
    if (ifdResult.hasError)
        return TiffInspectionResult(ifdResult.error().kind == ReadError.invalidRange
            ? TiffInspectionError.truncated : mapError(ifdResult.error().kind));

    TiffImageInfo info;
    info.header = header;
    foreach (i; 0 .. cast(size_t) count)
    {
        auto p = 8 + i * 20;
        auto tag = read16(ifd[p .. p + 2], header.littleEndian);
        auto type = read16(ifd[p + 2 .. p + 4], header.littleEndian);
        auto elements = read64(ifd[p + 4 .. p + 12], header.littleEndian);
        auto value = read64(ifd[p + 12 .. p + 20], header.littleEndian);
        auto reference = TiffTagReference(type, elements, value);
        auto scalar = scalarValue64(type, elements, value, header.littleEndian);
        switch (tag)
        {
            case 256: info.width = cast(uint) scalar; break;
            case 257: info.height = cast(uint) scalar; break;
            case 258: info.bitsPerSample = cast(uint) scalar; info.bitsPerSampleValues = reference; break;
            case 259: info.compression = cast(uint) scalar; break;
            case 262: info.photometric = cast(uint) scalar; break;
            case 277: info.samplesPerPixel = cast(uint) scalar; break;
            case 278: info.rowsPerStrip = cast(uint) scalar; break;
            case 284: info.planarConfiguration = cast(uint) scalar; break;
            case 317: info.predictor = cast(uint) scalar; break;
            case 322: info.tileWidth = cast(uint) scalar; break;
            case 323: info.tileLength = cast(uint) scalar; break;
            case 273: info.stripOffsets = reference; break;
            case 279: info.stripByteCounts = reference; break;
            case 324: info.tileOffsets = reference; info.tileCount = cast(uint) elements; info.tileOffsetType = type; break;
            case 325: info.tileByteCounts = reference; info.tileByteCountType = type; break;
            case 33550: info.modelPixelScaleCount = elements; info.modelPixelScaleValues = reference; break;
            case 33922: info.modelTiepointCount = elements; info.modelTiepointValues = reference; break;
            case 34264: info.modelTransformationCount = elements; info.modelTransformationValues = reference; break;
            case 34735: info.geoKeyDirectoryRef = reference; info.geoKeyDirectoryCount = elements; break;
            case 42113: info.noData = reference; info.noDataCount = elements; break;
            case 347: info.jpegTables = reference; break;
            default: break;
        }
    }
    auto nextPosition = 8 + cast(size_t) count * 20;
    info.nextIfdOffset = read64(ifd[nextPosition .. nextPosition + 8], header.littleEndian);
    if (info.width == 0 || info.height == 0 || info.samplesPerPixel == 0)
        return TiffInspectionResult(TiffInspectionError.invalidMagic);
    if (info.bitsPerSample != 0 && info.bitsPerSample != 8
        && info.bitsPerSample != 16 && info.bitsPerSample != 32)
        return TiffInspectionResult(TiffInspectionError.unsupportedVersion);
    if (!populateGeoTechnical(source, info))
        return TiffInspectionResult(TiffInspectionError.truncated);
    return TiffInspectionResult(TiffInspectionError.none, info.header, info);
}

/**
 * Decode a bounded ROI from the first uncompressed, single-band strip.
 *
 * This deliberately narrow decoder gate provides a complete typed
 * transport-to-pixels path. It rejects compression and tiled layouts until
 * their independent format gates pass.
 */
TiffDecodeResult decodeRegion(ByteSource source, size_t x, size_t y,
    size_t width, size_t height)
@safe
{
    auto inspection = inspect(source);
    if (!inspection.ok)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto decoded = decodeInfo(source, inspection.info, x, y, width, height);
    decoded.sourceInfo = inspection.info;
    decoded.levelIndex = 0;
    auto planned = planRegion(source, x, y, width, height);
    if (planned.ok)
    {
        decoded.bytesRequested = planned.plan.encodedBytes;
        decoded.decodedBytes = planned.plan.decodedBytes;
        decoded.fromNativeBlocks = planned.plan.blockCount != 0;
    }
    return decoded;
}

/** Decode a bounded ROI from a caller-selected classic-TIFF IFD level. */
TiffDecodeResult decodeRegionAtLevel(ByteSource source, size_t levelIndex,
    size_t x, size_t y, size_t width, size_t height)
@safe
{
    auto levels = inspectLevels(source);
    if (!levels.ok || levelIndex >= levels.levels.length)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto header = inspectHeader(source);
    if (!header.ok)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto level = inspectIfd(source, header.header,
        levels.levels[levelIndex].ifdOffset);
    if (!level.ok)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto decoded = decodeInfo(source, level.info, x, y, width, height);
    decoded.sourceInfo = level.info;
    decoded.levelIndex = levelIndex;
    auto planned = planRegionAtLevel(source, levelIndex, x, y, width, height);
    if (planned.ok)
    {
        decoded.bytesRequested = planned.plan.encodedBytes;
        decoded.decodedBytes = planned.plan.decodedBytes;
        decoded.fromNativeBlocks = planned.plan.blockCount != 0;
    }
    return decoded;
}

/** Select an overview for a requested output size and decode its scaled ROI. */
TiffDecodeResult decodeRegionAtBestLevel(ByteSource source, size_t x, size_t y,
    size_t width, size_t height, size_t targetWidth, size_t targetHeight)
@safe
{
    auto levels = inspectLevels(source);
    if (!levels.ok || levels.levels.length == 0)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto selected = selectLevel(levels.levels, targetWidth, targetHeight);
    if (!selected.ok)
        return TiffDecodeResult(selected.error);
    auto base = levels.levels[0];
    auto level = selected.selection.level;
    if (x > base.width || y > base.height || width > base.width - x
        || height > base.height - y)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto scaledX = cast(size_t)((cast(ulong) x * level.width) / base.width);
    auto scaledY = cast(size_t)((cast(ulong) y * level.height) / base.height);
    auto scaledRight = cast(size_t)(((cast(ulong) (x + width) * level.width)
        + base.width - 1) / base.width);
    auto scaledBottom = cast(size_t)(((cast(ulong) (y + height) * level.height)
        + base.height - 1) / base.height);
    if (scaledRight <= scaledX || scaledBottom <= scaledY)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto decoded = decodeRegionAtLevel(source, selected.selection.levelIndex,
        scaledX, scaledY, scaledRight - scaledX, scaledBottom - scaledY);
    decoded.usedOverview = selected.selection.levelIndex != 0;
    return decoded;
}

private TiffDecodeResult decodeInfo(ByteSource source, TiffImageInfo info,
    size_t x, size_t y, size_t width, size_t height)
@safe
{
    if (width == 0 || height == 0 || x > info.width || y > info.height
        || width > info.width - x || height > info.height - y)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    if ((info.compression != 1 && info.compression != 5
        && info.compression != 6 && info.compression != 7
        && info.compression != 8 && info.compression != 32773)
        || info.samplesPerPixel == 0
        || info.samplesPerPixel > 4 || (info.bitsPerSample != 8
            && info.bitsPerSample != 16) || info.planarConfiguration != 1
        || (info.stripOffsets.count == 0 && info.tileOffsets.count == 0)
        || (info.stripOffsets.count != 0 && info.tileOffsets.count != 0))
        return TiffDecodeResult(TiffDecodeError.unsupportedLayout);

    if (info.bitsPerSample == 0 && info.bitsPerSampleValues.count > 1)
    {
        auto length = cast(size_t) info.bitsPerSampleValues.count * 2;
        ubyte[] values = new ubyte[](length);
        auto bitsRead = source.read(ByteRange(info.bitsPerSampleValues.valueOffset,
            length), values[], ReadLimits(length));
        if (bitsRead.hasError)
            return TiffDecodeResult(TiffDecodeError.sourceFailure);
        auto first = read16(values[0 .. 2], info.header.littleEndian);
        foreach (i; 1 .. info.bitsPerSampleValues.count)
            if (read16(values[i * 2 .. i * 2 + 2], info.header.littleEndian) != first)
                return TiffDecodeResult(TiffDecodeError.unsupportedLayout);
        info.bitsPerSample = first;
    }

    auto bytesPerSample = info.bitsPerSample / 8;
    auto samplesPerPixel = cast(size_t) info.samplesPerPixel;
    if (samplesPerPixel > size_t.max / bytesPerSample)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto bytesPerPixel = samplesPerPixel * bytesPerSample;
    if (bytesPerPixel > size_t.max / cast(size_t) info.width)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto bytesPerRow = cast(size_t) info.width * bytesPerPixel;
    if (bytesPerRow > size_t.max / cast(size_t) info.height
        || width > size_t.max / height
        || width * height > size_t.max / bytesPerPixel)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);

    if (info.tileOffsets.count != 0)
        return decodeTiled(source, info, x, y, width, height, bytesPerPixel);

    if (info.stripByteCounts.count != info.stripOffsets.count
        || info.rowsPerStrip == 0)
        return TiffDecodeResult(TiffDecodeError.unsupportedLayout);
    auto output = new ubyte[](width * height * bytesPerPixel);
    auto jpegTables = readTagBytes(source, info.jpegTables,
        info.header.littleEndian);
    if (info.jpegTables.count != 0 && jpegTables.length == 0)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto offsets = readLongValues(source, info.stripOffsets, info.header.littleEndian);
    auto byteCounts = readLongValues(source, info.stripByteCounts, info.header.littleEndian);
    if (offsets.length != info.stripOffsets.count
        || byteCounts.length != info.stripByteCounts.count)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);

    foreach (row; 0 .. height)
    {
        auto sourceRow = y + row;
        auto strip = sourceRow / info.rowsPerStrip;
        if (strip >= offsets.length)
            return TiffDecodeResult(TiffDecodeError.truncated);
        auto stripRows = info.rowsPerStrip;
        if (stripRows > info.height - strip * info.rowsPerStrip)
            stripRows = cast(uint)(info.height - strip * info.rowsPerStrip);
        auto stripBytes = cast(size_t) stripRows * bytesPerRow;
        if (byteCounts[strip] < stripBytes)
            return TiffDecodeResult(TiffDecodeError.truncated);
        auto encodedBytes = info.compression == 1 ? stripBytes
            : cast(size_t) byteCounts[strip];
        auto encoded = new ubyte[](encodedBytes);
        auto read = source.read(ByteRange(offsets[strip], encodedBytes), encoded[],
            ReadLimits(encodedBytes));
        if (read.hasError || read.value.bytesRead < encodedBytes)
            return TiffDecodeResult(!read.hasError
                ? TiffDecodeError.truncated : TiffDecodeError.sourceFailure);
        auto payload = new ubyte[](stripBytes);
        if (!decodePayload(info.compression, encoded[], payload[],
            cast(size_t) info.width, stripRows, samplesPerPixel, jpegTables[]))
            return TiffDecodeResult(TiffDecodeError.truncated);
        if (info.predictor == 2)
            applyPredictor(payload, cast(size_t) info.width, stripRows,
                bytesPerPixel);
        else if (info.predictor != 0 && info.predictor != 1)
            return TiffDecodeResult(TiffDecodeError.unsupportedLayout);
        auto sourceStart = (sourceRow - strip * info.rowsPerStrip) * bytesPerRow
            + x * bytesPerPixel;
        auto destinationStart = row * width * bytesPerPixel;
        output[destinationStart .. destinationStart + width * bytesPerPixel] =
            payload[sourceStart .. sourceStart + width * bytesPerPixel];
    }
    auto format = info.bitsPerSample == 8 ? SampleFormat.u8 : SampleFormat.u16;
    auto description = ImageRegionInfo(width, height, info.samplesPerPixel,
        format, PixelLayout.interleaved, width * bytesPerPixel,
        bytesPerSample, 0);
    return TiffDecodeResult(TiffDecodeError.none,
        ImageRegion(description, x, y, output));
}

private bool decodePayload(uint compression, scope const(ubyte)[] encoded,
    scope ubyte[] decoded, size_t width, size_t height, size_t components,
    scope const(ubyte)[] jpegTables = null)
@safe
{
    final switch (compression)
    {
    case 1:
        if (encoded.length < decoded.length)
            return false;
        decoded[] = encoded[0 .. decoded.length];
        return true;
    case 5:
        LzwWorkspace workspace;
        auto result = decodeLzw(encoded, decoded, workspace);
        return result.status == DecodeStatus.done && result.produced == decoded.length;
    case 8:
        InflateWorkspace workspace;
        auto result = inflateZlib(encoded, decoded, workspace);
        return result.status == DecodeStatus.done && result.produced == decoded.length;
    case 32773:
        auto result = decodePackBits(encoded, decoded);
        return result.status == DecodeStatus.done && result.produced == decoded.length;
    case 6, 7:
        if (decoded.length != width * height * components)
            return false;
        auto jpeg = composeJpeg(jpegTables, encoded);
        if (components == 1)
        {
            auto result = decodeJpeg(jpeg[], decoded, width,
                Limits(64 * 1024 * 1024, cast(ulong) width * height));
            return result.ok && result.written == decoded.length;
        }
        if (components != 3)
            return false;
        auto frame = inspectJpegFrame(jpeg[]);
        if (!frame.ok || frame.info.components != 3)
            return false;
        foreach (c; 0 .. 3)
            if (frame.horizontal[c] != 1 || frame.vertical[c] != 1)
                return false;
        auto planes = new ubyte[][3];
        foreach (ref plane; planes)
            plane = new ubyte[](width * height);
        MutablePlane[3] destinations;
        foreach (c; 0 .. 3)
            destinations[c] = MutablePlane(planes[c], width);
        auto result = decodeJpegPlanes(jpeg[], destinations[],
            Limits(64 * 1024 * 1024, cast(ulong) width * height));
        if (!result.ok)
            return false;
        foreach (pixel; 0 .. width * height)
            foreach (component; 0 .. 3)
                decoded[pixel * 3 + component] = planes[component][pixel];
        return true;
    }
}

private ubyte[] composeJpeg(scope const(ubyte)[] tables,
    scope const(ubyte)[] encoded)
@safe
{
    if (tables.length == 0)
        return encoded.dup;
    if (tables.length >= 2 && encoded.length >= 2
        && tables[0] == 0xff && tables[1] == 0xd8
        && encoded[0] == 0xff && encoded[1] == 0xd8)
    {
        auto end = tables.length;
        if (end >= 2 && tables[end - 2] == 0xff && tables[end - 1] == 0xd9)
            end -= 2;
        auto result = new ubyte[](end + encoded.length - 2);
        result[0 .. end] = tables[0 .. end];
        result[end .. $] = encoded[2 .. $];
        return result;
    }
    return encoded.dup;
}

/** Plan the bounded strip/tile reads for a region without decoding pixels. */
TiffPlanResult planRegion(ByteSource source, size_t x, size_t y,
    size_t width, size_t height)
@safe
{
    auto inspection = inspect(source);
    if (!inspection.ok)
        return TiffPlanResult(TiffDecodeError.sourceFailure);
    return planInfo(source, inspection.info, 0, x, y, width, height);
}

/** Plan a region against a caller-selected IFD level. */
TiffPlanResult planRegionAtLevel(ByteSource source, size_t levelIndex,
    size_t x, size_t y, size_t width, size_t height)
@safe
{
    auto levels = inspectLevels(source);
    if (!levels.ok || levelIndex >= levels.levels.length)
        return TiffPlanResult(TiffDecodeError.invalidRegion);
    auto header = inspectHeader(source);
    if (!header.ok)
        return TiffPlanResult(TiffDecodeError.sourceFailure);
    auto level = inspectIfd(source, header.header, levels.levels[levelIndex].ifdOffset);
    if (!level.ok)
        return TiffPlanResult(TiffDecodeError.sourceFailure);
    return planInfo(source, level.info, levelIndex, x, y, width, height);
}

private TiffPlanResult planInfo(ByteSource source, TiffImageInfo info,
    size_t levelIndex, size_t x, size_t y, size_t width, size_t height)
@safe
{
    if (width == 0 || height == 0 || x > info.width || y > info.height
        || width > info.width - x || height > info.height - y)
        return TiffPlanResult(TiffDecodeError.invalidRegion);
    TiffRegionPlan plan = TiffRegionPlan(info, levelIndex, x, y, width, height);
    auto bits = info.bitsPerSample == 0 ? 0 : info.bitsPerSample;
    if (bits != 0 && bits % 8 == 0)
    {
        auto bytesPerSample = bits / 8;
        plan.decodedBytes = cast(ulong) width * height
            * info.samplesPerPixel * bytesPerSample;
    }
    if (info.tileOffsets.count != 0)
    {
        if (info.tileWidth == 0 || info.tileLength == 0)
            return TiffPlanResult(TiffDecodeError.unsupportedLayout);
        auto across = (info.width + info.tileWidth - 1) / info.tileWidth;
        auto firstX = x / info.tileWidth;
        auto lastX = (x + width - 1) / info.tileWidth;
        auto firstY = y / info.tileLength;
        auto lastY = (y + height - 1) / info.tileLength;
        plan.blockCount = (lastX - firstX + 1) * (lastY - firstY + 1);
        auto counts = readLongValues(source, info.tileByteCounts, info.header.littleEndian);
        foreach (tileY; firstY .. lastY + 1)
            foreach (tileX; firstX .. lastX + 1)
            {
                auto index = tileY * across + tileX;
                if (index >= counts.length)
                    return TiffPlanResult(TiffDecodeError.truncated);
                plan.encodedBytes += counts[index];
            }
    }
    else if (info.stripOffsets.count != 0)
    {
        if (info.rowsPerStrip == 0)
            return TiffPlanResult(TiffDecodeError.unsupportedLayout);
        auto first = y / info.rowsPerStrip;
        auto last = (y + height - 1) / info.rowsPerStrip;
        plan.blockCount = last - first + 1;
        auto counts = readLongValues(source, info.stripByteCounts, info.header.littleEndian);
        if (last >= counts.length)
            return TiffPlanResult(TiffDecodeError.truncated);
        foreach (index; first .. last + 1)
            plan.encodedBytes += counts[index];
    }
    else
        return TiffPlanResult(TiffDecodeError.unsupportedLayout);
    return TiffPlanResult(TiffDecodeError.none, plan);
}

/** Inspect the classic-TIFF IFD chain as potential resolution levels. */
TiffLevelsResult inspectLevels(ByteSource source)
@safe
{
    auto header = inspectHeader(source);
    if (!header.ok)
        return TiffLevelsResult(TiffDecodeError.sourceFailure);
    TiffLevelInfo[] parsed;
    auto parsedOffset = header.header.firstIfdOffset;
    while (parsedOffset != 0)
    {
        auto level = inspectIfd(source, header.header, parsedOffset);
        if (!level.ok)
            return TiffLevelsResult(TiffDecodeError.sourceFailure);
        parsed ~= TiffLevelInfo(parsedOffset, level.info.width,
            level.info.height, level.info.nextIfdOffset);
        parsedOffset = level.info.nextIfdOffset;
    }
    return TiffLevelsResult(TiffDecodeError.none, parsed);
}

/**
 * Select the coarsest available level that still covers the requested output
 * dimensions. Ties prefer the first level in the IFD chain.
 */
TiffSelectionResult selectLevel(scope const(TiffLevelInfo)[] levels,
    size_t requestedWidth, size_t requestedHeight)
@safe pure nothrow @nogc
{
    if (levels.length == 0 || requestedWidth == 0 || requestedHeight == 0)
        return TiffSelectionResult(TiffDecodeError.invalidRegion);
    size_t selected = size_t.max;
    ulong selectedArea = ulong.max;
    foreach (i, level; levels)
    {
        if (level.width < requestedWidth || level.height < requestedHeight)
            continue;
        auto area = cast(ulong) level.width * level.height;
        if (area < selectedArea)
        {
            selected = i;
            selectedArea = area;
        }
    }
    if (selected == size_t.max)
        return TiffSelectionResult(TiffDecodeError.invalidRegion);
    return TiffSelectionResult(TiffDecodeError.none,
        TiffLevelSelection(selected, levels[selected]));
}

unittest
{
    const TiffLevelInfo[] levels =
    [
        TiffLevelInfo(8, 4096, 4096, 0),
        TiffLevelInfo(128, 1024, 1024, 0),
        TiffLevelInfo(256, 256, 256, 0)
    ];
    auto selected = selectLevel(levels, 800, 600);
    assert(selected.ok);
    assert(selected.selection.levelIndex == 1);
    assert(!selectLevel(levels, 8192, 8192).ok);
}

private TiffDecodeResult decodeTiled(ByteSource source, TiffImageInfo info,
    size_t x, size_t y, size_t width, size_t height, size_t bytesPerPixel)
@safe
{
    if (info.tileWidth == 0 || info.tileLength == 0
        || info.tileByteCounts.count != info.tileOffsets.count)
        return TiffDecodeResult(TiffDecodeError.unsupportedLayout);
    auto offsets = readLongValues(source, info.tileOffsets, info.header.littleEndian);
    auto counts = readLongValues(source, info.tileByteCounts, info.header.littleEndian);
    if (offsets.length == 0 || counts.length != offsets.length)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    if (info.tileWidth > size_t.max / bytesPerPixel)
        return TiffDecodeResult(TiffDecodeError.invalidRegion);
    auto samplesPerPixel = cast(size_t) info.samplesPerPixel;
    auto bytesPerSample = info.bitsPerSample / 8;
    auto tileRowBytes = cast(size_t) info.tileWidth * bytesPerPixel;
    auto tileBytes = tileRowBytes * cast(size_t) info.tileLength;
    auto output = new ubyte[](width * height * bytesPerPixel);
    auto jpegTables = readTagBytes(source, info.jpegTables,
        info.header.littleEndian);
    if (info.jpegTables.count != 0 && jpegTables.length == 0)
        return TiffDecodeResult(TiffDecodeError.sourceFailure);
    auto tilesAcross = (info.width + info.tileWidth - 1) / info.tileWidth;
    auto firstTileX = x / info.tileWidth;
    auto lastTileX = (x + width - 1) / info.tileWidth;
    auto firstTileY = y / info.tileLength;
    auto lastTileY = (y + height - 1) / info.tileLength;
    foreach (tileY; firstTileY .. lastTileY + 1)
        foreach (tileX; firstTileX .. lastTileX + 1)
        {
            auto tileIndex = tileY * tilesAcross + tileX;
            if (tileIndex >= offsets.length)
                return TiffDecodeResult(TiffDecodeError.truncated);
            auto encodedBytes = info.compression == 1
                ? tileBytes : cast(size_t) counts[tileIndex];
            if (encodedBytes == 0)
                return TiffDecodeResult(TiffDecodeError.truncated);
            auto encoded = new ubyte[](encodedBytes);
            auto read = source.read(ByteRange(offsets[tileIndex], encodedBytes),
                encoded[], ReadLimits(encodedBytes));
            if (read.hasError || read.value.bytesRead < encodedBytes)
                return TiffDecodeResult(TiffDecodeError.sourceFailure);
            auto tile = new ubyte[](tileBytes);
            if (!decodePayload(info.compression, encoded[], tile[],
                info.tileWidth, info.tileLength, samplesPerPixel, jpegTables[]))
                return TiffDecodeResult(TiffDecodeError.truncated);
            if (info.predictor == 2)
                applyPredictor(tile, info.tileWidth, info.tileLength, bytesPerPixel);
            else if (info.predictor != 0 && info.predictor != 1)
                return TiffDecodeResult(TiffDecodeError.unsupportedLayout);
            auto tileLeft = tileX * info.tileWidth;
            auto tileTop = tileY * info.tileLength;
            auto copyLeft = x > tileLeft ? x : tileLeft;
            auto copyTop = y > tileTop ? y : tileTop;
            auto copyRight = (x + width) < (tileLeft + info.tileWidth)
                ? x + width : tileLeft + info.tileWidth;
            auto copyBottom = (y + height) < (tileTop + info.tileLength)
                ? y + height : tileTop + info.tileLength;
            foreach (row; copyTop .. copyBottom)
            {
                auto sourceStart = (row - tileTop) * tileRowBytes
                    + (copyLeft - tileLeft) * bytesPerPixel;
                auto destinationStart = (row - y) * width * bytesPerPixel
                    + (copyLeft - x) * bytesPerPixel;
                auto count = (copyRight - copyLeft) * bytesPerPixel;
                output[destinationStart .. destinationStart + count] =
                    tile[sourceStart .. sourceStart + count];
            }
        }
    auto format = info.bitsPerSample == 8 ? SampleFormat.u8 : SampleFormat.u16;
    auto description = ImageRegionInfo(width, height, info.samplesPerPixel,
        format, PixelLayout.interleaved, width * bytesPerPixel,
        bytesPerSample, 0);
    return TiffDecodeResult(TiffDecodeError.none,
        ImageRegion(description, x, y, output));
}

private double bitsAsDouble(ulong bits) @trusted pure nothrow @nogc
{
    return *cast(double*)&bits;
}

private double[] readDoubleValues(ByteSource source, TiffTagReference reference,
    bool little) @safe
{
    if (reference.count == 0 || reference.type != 12
        || reference.count > size_t.max / 8)
        return null;
    auto values = new double[](cast(size_t) reference.count);
    auto bytes = new ubyte[](values.length * 8);
    auto result = source.read(ByteRange(reference.valueOffset, bytes.length),
        bytes[], ReadLimits(bytes.length));
    if (result.hasError || result.value.bytesRead < bytes.length)
        return null;
    foreach (i; 0 .. values.length)
        values[i] = bitsAsDouble(read64(bytes[i * 8 .. i * 8 + 8], little));
    return values;
}

private bool populateGeoTechnical(ByteSource source, ref TiffImageInfo info)
@safe
{
    if (info.geoKeyDirectoryCount != 0)
    {
        if (info.geoKeyDirectoryRef.type != 3)
            return false;
        if (info.geoKeyDirectoryCount > size_t.max / 2)
            return false;
        auto bytes = new ubyte[](cast(size_t) info.geoKeyDirectoryCount * 2);
        if (info.geoKeyDirectoryCount <= 2)
        {
            foreach (i; 0 .. bytes.length)
                bytes[i] = cast(ubyte)(info.geoKeyDirectoryRef.valueOffset
                    >> (info.header.littleEndian ? i * 8
                        : (bytes.length - 1 - i) * 8));
        }
        else
        {
            auto read = source.read(ByteRange(info.geoKeyDirectoryRef.valueOffset,
                bytes.length), bytes[], ReadLimits(bytes.length));
            if (read.hasError || read.value.bytesRead < bytes.length)
                return false;
        }
        info.geoKeyDirectoryValues = new ushort[](cast(size_t) info.geoKeyDirectoryCount);
        foreach (i; 0 .. info.geoKeyDirectoryValues.length)
            info.geoKeyDirectoryValues[i] = read16(bytes[i * 2 .. i * 2 + 2],
                info.header.littleEndian);
        if (info.geoKeyDirectoryValues.length < 4
            || info.geoKeyDirectoryValues[0] != 1
            || info.geoKeyDirectoryValues.length
                < 4 + info.geoKeyDirectoryValues[3] * 4)
            return false;
        info.hasModelTypeGeoKey = info.geoKeyShort(1024,
            info.modelTypeGeoKey);
        info.hasRasterTypeGeoKey = info.geoKeyShort(1025,
            info.rasterTypeGeoKey);
        info.hasGeographicCrsGeoKey = info.geoKeyShort(2048,
            info.geographicCrsGeoKey);
        info.hasProjectedCrsGeoKey = info.geoKeyShort(3072,
            info.projectedCrsGeoKey);
    }
    if (info.noDataCount != 0)
    {
        info.noDataValue = readTagBytes(source, info.noData,
            info.header.littleEndian);
        if (info.noDataValue.length != info.noDataCount)
            return false;
    }
    if (info.modelPixelScaleCount != 0)
    {
        info.modelPixelScale = readDoubleValues(source,
            info.modelPixelScaleValues, info.header.littleEndian);
        if (info.modelPixelScale.length != info.modelPixelScaleCount)
            return false;
    }
    if (info.modelTiepointCount != 0)
    {
        info.modelTiepoint = readDoubleValues(source,
            info.modelTiepointValues, info.header.littleEndian);
        if (info.modelTiepoint.length != info.modelTiepointCount)
            return false;
    }
    if (info.modelTransformationCount != 0)
    {
        info.modelTransformation = readDoubleValues(source,
            info.modelTransformationValues, info.header.littleEndian);
        if (info.modelTransformation.length != info.modelTransformationCount)
            return false;
    }
    return true;
}

private ulong[] readLongValues(ByteSource source, TiffTagReference reference, bool little)
@safe
{
    if (reference.count == 0)
        return null;
    if (reference.count == 1 && (reference.type == 4 || reference.type == 16
        || reference.type == 17 || reference.type == 18))
        return [reference.valueOffset];
    if (reference.type != 3 && reference.type != 4 && reference.type != 16
        && reference.type != 17 && reference.type != 18)
        return null;
    auto elementBytes = reference.type == 3 ? 2 :
        (reference.type == 16 || reference.type == 17 || reference.type == 18) ? 8 : 4;
    if (reference.count == 1 && reference.type == 3)
        return [little ? reference.valueOffset & 0xffff : reference.valueOffset >> 16];
    if (reference.type == 3 && reference.count <= 2)
    {
        auto values = new ulong[](reference.count);
        foreach (i; 0 .. reference.count)
            values[i] = little
                ? (reference.valueOffset >> (i * 16)) & 0xffff
                : (reference.valueOffset >> ((1 - i) * 16)) & 0xffff;
        return values;
    }
    auto length = cast(size_t) reference.count * elementBytes;
    ubyte[] bytes = new ubyte[](length);
    auto result = source.read(ByteRange(reference.valueOffset, length), bytes[],
        ReadLimits(length));
    if (result.hasError)
        return null;
    auto values = new ulong[](reference.count);
    foreach (i; 0 .. reference.count)
        values[i] = reference.type == 3
            ? read16(bytes[i * 2 .. i * 2 + 2], little)
            : reference.type == 4
                ? read32(bytes[i * 4 .. i * 4 + 4], little)
                : read64(bytes[i * 8 .. i * 8 + 8], little);
    return values;
}

private ubyte[] readTagBytes(ByteSource source, TiffTagReference reference,
    bool little)
@safe
{
    if (reference.count == 0 || reference.count > size_t.max)
        return null;
    const length = cast(size_t) reference.count;
    ubyte[] bytes = new ubyte[](length);
    if (length <= 8)
    {
        foreach (i; 0 .. length)
            bytes[i] = cast(ubyte)(reference.valueOffset >>
                (little ? i * 8 : (length - 1 - i) * 8));
        return bytes;
    }
    auto result = source.read(ByteRange(reference.valueOffset, length), bytes[],
        ReadLimits(length));
    return !result.hasError ? bytes : null;
}

private void applyPredictor(scope ubyte[] bytes, size_t width, size_t rows,
    size_t bytesPerPixel)
@safe pure nothrow @nogc
{
    if (bytesPerPixel == 0 || width == 0)
        return;
    auto rowBytes = width * bytesPerPixel;
    foreach (row; 0 .. rows)
    {
        auto start = row * rowBytes;
        foreach (pixel; 1 .. width)
        {
            auto current = start + pixel * bytesPerPixel;
            auto previous = current - bytesPerPixel;
            foreach (b; 0 .. bytesPerPixel)
                bytes[current + b] += bytes[previous + b];
        }
    }
}

private TiffInspectionResult validateHeader(bool little, ushort tiffVersion,
    ulong offset, bool bigTiff)
@safe pure nothrow @nogc
{
    if (tiffVersion != 42 && tiffVersion != 43)
        return TiffInspectionResult(TiffInspectionError.invalidMagic);
    if (offset < 8)
        return TiffInspectionResult(TiffInspectionError.invalidRange);
    auto header = TiffHeader(little, tiffVersion, offset, bigTiff);
    return TiffInspectionResult(TiffInspectionError.none, header, TiffImageInfo.init);
}

private ushort read16(const(ubyte)[] bytes, bool little)
@safe pure nothrow @nogc
{
    return little ? cast(ushort)(bytes[0] | (bytes[1] << 8))
        : cast(ushort)((bytes[0] << 8) | bytes[1]);
}

private uint read32(const(ubyte)[] bytes, bool little)
@safe pure nothrow @nogc
{
    return little ? cast(uint)(bytes[0] | (bytes[1] << 8)
        | (bytes[2] << 16) | (bytes[3] << 24))
        : cast(uint)((bytes[0] << 24) | (bytes[1] << 16)
            | (bytes[2] << 8) | bytes[3]);
}

private ulong read64(const(ubyte)[] bytes, bool little)
@safe pure nothrow @nogc
{
    ulong value;
    if (little)
        foreach_reverse (i; 0 .. 8) value = (value << 8) | bytes[i];
    else
        foreach (i; 0 .. 8) value = (value << 8) | bytes[i];
    return value;
}

private uint scalarValue(ushort type, uint count, uint value, bool little)
@safe pure nothrow @nogc
{
    if (count != 1)
        return 0;
    if (type == 3)
        return little ? value & 0xffff : value >> 16;
    if (type == 4)
        return value;
    return 0;
}

private ulong scalarValue64(ushort type, ulong count, ulong value, bool little)
@safe pure nothrow @nogc
{
    if (count != 1)
        return 0;
    if (type == 3)
        return little ? value & 0xffff : value >> 48;
    if (type == 4)
        return little ? value & 0xffff_ffffUL : value >> 32;
    if (type == 16 || type == 17 || type == 18)
        return value;
    return 0;
}

private TiffInspectionError mapError(ReadError error)
@safe pure nothrow @nogc
{
    final switch (error)
    {
        case ReadError.none: return TiffInspectionError.none;
        case ReadError.invalidRange: return TiffInspectionError.invalidRange;
        case ReadError.endOfSource:
        case ReadError.destinationTooSmall:
        case ReadError.limitExceeded: return TiffInspectionError.truncated;
        case ReadError.rangeUnavailable:
        case ReadError.sourceFailure: return TiffInspectionError.sourceFailure;
    }
}

unittest
{
    import transport : MemorySource;

    ubyte[] little = [ubyte('I'), ubyte('I'), 42, 0, 8, 0, 0, 0];
    auto littleResult = inspectHeader(new MemorySource(little));
    assert(littleResult.ok);
    assert(littleResult.header.littleEndian);
    assert(littleResult.header.firstIfdOffset == 8);

    ubyte[] big = [ubyte('M'), ubyte('M'), 0, 42, 0, 0, 0, 8];
    auto bigResult = inspectHeader(new MemorySource(big));
    assert(bigResult.ok);
    assert(!bigResult.header.littleEndian);

    ubyte[] truncated = [ubyte('I'), ubyte('I')];
    auto truncatedResult = inspectHeader(new MemorySource(truncated));
    assert(truncatedResult.error == TiffInspectionError.truncated);
}

unittest
{
    // Two rows of four UInt8 samples encoded with horizontal differencing.
    ubyte[] encoded = [1, 1, 1, 1, 4, 1, 1, 1];
    applyPredictor(encoded, 4, 2, 1);
    assert(encoded == [1, 2, 3, 4, 4, 5, 6, 7]);

    // Interleaved two-byte samples are reconstructed byte-wise without
    // changing the declared sample representation.
    ubyte[] interleaved = [1, 0, 1, 0];
    applyPredictor(interleaved, 2, 1, 2);
    assert(interleaved == [1, 0, 2, 0]);
}

unittest
{
    // Minimal little-endian 2x2 UInt8 TIFF with one uncompressed strip.
    ubyte[] file = new ubyte[](126);
    file[0 .. 2] = [ubyte('I'), ubyte('I')];
    file[2] = 42;
    file[4] = 8;
    file[8] = 9;
    void put16(size_t p, ushort value)
    {
        file[p] = cast(ubyte) value;
        file[p + 1] = cast(ubyte) (value >> 8);
    }
    void put32(size_t p, uint value)
    {
        file[p] = cast(ubyte) value;
        file[p + 1] = cast(ubyte) (value >> 8);
        file[p + 2] = cast(ubyte) (value >> 16);
        file[p + 3] = cast(ubyte) (value >> 24);
    }
    void entry(size_t index, ushort tag, ushort type, uint count, uint value)
    {
        auto p = 10 + index * 12;
        put16(p, tag);
        put16(p + 2, type);
        put32(p + 4, count);
        put32(p + 8, value);
    }
    entry(0, 256, 3, 1, 2);
    entry(1, 257, 3, 1, 2);
    entry(2, 258, 3, 1, 8);
    entry(3, 259, 3, 1, 1);
    entry(4, 262, 3, 1, 1);
    entry(5, 273, 4, 1, 122);
    entry(6, 277, 3, 1, 1);
    entry(7, 278, 4, 1, 2);
    entry(8, 279, 4, 1, 4);
    file[122 .. 126] = [1, 2, 3, 4];

    import transport : MemorySource;
    auto source = new MemorySource(file);
    auto info = inspect(source);
    assert(info.ok);
    assert(info.info.width == 2 && info.info.height == 2);
    auto decoded = decodeRegion(source, 1, 0, 1, 2);
    assert(decoded.ok);
    assert(decoded.region.info.componentCount == 1);
    assert(decoded.region.data == [2, 4]);
    assert(decoded.sourceInfo.width == 2 && decoded.sourceInfo.height == 2);
    assert(decoded.sourceInfo.compression == 1);
}

unittest
{
    // GeoKeyDirectoryTag uses a four-SHORT header followed by four-SHORT
    // entries: key id, location, count and value/offset.
    TiffImageInfo info;
    info.geoKeyDirectoryValues = [
        cast(ushort)1, 1, 0, 1,
        cast(ushort)1024, 0, 1, 1
    ];
    ushort value;
    assert(info.geoKeyShort(1024, value) && value == 1);
    assert(!info.geoKeyShort(1025, value));

    auto malformed = info;
    malformed.geoKeyDirectoryValues[3] = 2;
    assert(!malformed.geoKeyShort(1024, value));

    auto external = info;
    external.geoKeyDirectoryValues[5] = 34736;
    assert(!external.geoKeyShort(1024, value));
}

unittest
{
    import transport : MemorySource;

    ubyte[] tiffHeader = ['M', 'M', 0, 42, 0, 0, 0, 8];
    auto detected = detectFormat(new MemorySource(tiffHeader));
    assert(detected.ok);
    assert(detected.format == ImageFormat.tiff);

    ubyte[] unknown = ['N', 'O', 'P', 'E', 0, 0, 0, 0];
    auto rejected = detectFormat(new MemorySource(unknown));
    assert(rejected.ok);
    assert(rejected.format == ImageFormat.unknown);
}

unittest
{
    // Decoder-level metadata receipt for odd dimensions and both subsampling
    // layouts. The padded source stride also proves that the fixture is not
    // relying on tightly packed RGB rows.
    import imageio.region : ComponentRole, SourceModel;

    const width = 5, height = 3, stride = width * 3 + 2;
    auto rgb = new ubyte[](stride * height);
    foreach (y; 0 .. height)
        foreach (x; 0 .. width)
        {
            auto p = y * stride + x * 3;
            rgb[p .. p + 3] = [cast(ubyte)(x * 20), cast(ubyte)(y * 30), 90];
        }

    foreach (sampling; [Sampling.s420, Sampling.s422])
    {
        auto encoded = new ubyte[](64 * 1024);
        auto written = encodeJpeg(Info(cast(uint)width, cast(uint)height, 3),
            rgb, stride, encoded, EncodeOptions(75, sampling, 1));
        assert(written.ok);

        auto decoded = decodeJpegPlanes(encoded[0 .. written.written]);
        assert(decoded.ok);
        assert(decoded.region.info.sourceModel == SourceModel.yCbCr);
        assert(decoded.region.info.colorMetadata.state == MetadataState.known);
        assert(decoded.region.info.colorMetadata.modelState == MetadataState.known);
        assert(decoded.region.info.colorMetadata.bitDepth == 8);
        assert(decoded.region.info.colorMetadata.bitDepthState == MetadataState.known);
        assert(decoded.region.info.colorMetadata.rangeState == MetadataState.absent);
        assert(decoded.region.info.colorMetadata.transferState == MetadataState.absent);
        assert(decoded.region.info.colorMetadata.primariesState == MetadataState.absent);
        assert(decoded.region.planes.length == 3);
        assert(decoded.region.planes[0].info.role == ComponentRole.luma);
        assert(decoded.region.planes[1].info.role == ComponentRole.chromaBlue);
        assert(decoded.region.planes[2].info.role == ComponentRole.chromaRed);

        const expectedHeight = sampling == Sampling.s420 ? 2 : 3;
        assert(decoded.region.planes[1].info.horizontalSampling == 1);
        assert(decoded.region.planes[1].info.verticalSampling == 1);
        assert(decoded.region.planes[1].width == (width + 1) / 2);
        assert(decoded.region.planes[1].height == expectedHeight);
        assert(!decoded.region.planes[1].info.geometry.valid);
        assert(decoded.region.planes[1].info.geometry.horizontalFactor == 2);
        assert(decoded.region.planes[1].info.geometry.verticalFactor
            == (sampling == Sampling.s420 ? 2 : 1));
        assert(decoded.region.planes[1].originX == 0
            && decoded.region.planes[1].originY == 0);

        foreach (oy; 0 .. 2)
            foreach (ox; 0 .. 2)
            {
                auto roi = decodeJpegRegion(encoded[0 .. written.written], ox, oy,
                    3, 2);
                assert(roi.ok);
                assert(roi.region.originX == ox && roi.region.originY == oy);
                assert(roi.region.info.width == 3 && roi.region.info.height == 2);
                assert(roi.region.planes[0].originX == ox
                    && roi.region.planes[0].originY == oy);
                auto chroma = roi.region.planes[1];
                assert(chroma.info.role == ComponentRole.chromaBlue);
                assert(chroma.referenceOffsetX.numerator == ox % 2
                    && chroma.referenceOffsetX.denominator == 2);
                assert(chroma.referenceOffsetY.numerator
                    == (sampling == Sampling.s420 ? oy % 2 : 0));
                assert(chroma.referenceOffsetY.denominator
                    == (sampling == Sampling.s420 ? 2 : 1));
                auto sx = sampleCenter(chroma.originX, 0,
                    chroma.info.geometry.horizontalFactor,
                    chroma.referenceOffsetX);
                auto sy = sampleCenter(chroma.originY, 0,
                    chroma.info.geometry.verticalFactor,
                    chroma.referenceOffsetY);
                assert(sx.valid && sy.valid);
            }

        // Boundary-ending and one-pixel windows must retain the same public
        // origin/phase contract; these are the cases most likely to expose
        // accidental floor-division or zero-sized plane handling.
        foreach (xy; [[size_t(0), size_t(0)], [size_t(4), size_t(0)],
            [size_t(0), size_t(2)], [size_t(4), size_t(2)]])
        {
            auto edge = decodeJpegRegion(encoded[0 .. written.written],
                xy[0], xy[1], 1, 1);
            assert(edge.ok);
            assert(edge.region.info.width == 1 && edge.region.info.height == 1);
            assert(edge.region.originX == xy[0] && edge.region.originY == xy[1]);
            auto edgeChroma = edge.region.planes[1];
            assert(edgeChroma.width >= 1 && edgeChroma.height >= 1);
            assert(edgeChroma.referenceOffsetX.numerator == xy[0] % 2);
            assert(edgeChroma.referenceOffsetY.numerator
                == (sampling == Sampling.s420 ? xy[1] % 2 : 0));
        }

        auto invalid = decodeJpegRegion(encoded[0 .. written.written],
            width, 0, 1, 1);
        assert(!invalid.ok && invalid.error == TiffDecodeError.invalidRegion);
    }
}
