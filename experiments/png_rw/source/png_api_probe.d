/// Compile-only boundary probe; not a substitute for an imagery-d consumer.
module png_api_probe;

import png_research;
import compression.deflate : InflateWorkspace;
import compression.encode : HashChainMatchFinder;

/// A caller owns source, destination, both decoder workspaces and the codec state.
/// No colour- or image-semantic type is required by the technical I/O call.
Result borrowedRead(scope const(ubyte)[] encoded, scope ubyte[] idatScratch,
    scope ubyte[] scanlineScratch, scope ubyte[] pixels, size_t rowStride,
    ref InflateWorkspace decoder) @safe pure nothrow @nogc
{
    return decodePng(encoded, idatScratch, scanlineScratch, pixels,
        rowStride, decoder);
}

/// The writer receives already-selected technical samples; conversion and
/// semantic band binding are not hidden in its codec API.
Result borrowedWrite(Info shape, scope const(ubyte)[] pixels, size_t rowStride,
    MetadataPolicy lossPolicy, scope ubyte[] scanlineScratch,
    scope ubyte[] zlibScratch, scope ubyte[] encoded)
    @safe pure nothrow @nogc
{
    return encodePng(shape, pixels, rowStride, lossPolicy,
        scanlineScratch, zlibScratch, encoded);
}

/// The faster provider path receives its caller-owned match finder explicitly.
Result borrowedHashWrite(Info shape, scope const(ubyte)[] pixels,
    size_t rowStride, MetadataPolicy lossPolicy, scope ubyte[] scanlineScratch,
    scope ubyte[] zlibScratch, scope ubyte[] encoded,
    ref HashChainMatchFinder finder) @safe pure nothrow @nogc
{
    return encodePngHashChain(shape, pixels, rowStride, lossPolicy,
        scanlineScratch, zlibScratch, encoded, finder);
}

/// Compile proof that the 295-KiB finder can be stack-owned in @safe/@nogc D.
Result stackHashWrite(Info shape, scope const(ubyte)[] pixels,
    size_t rowStride, MetadataPolicy lossPolicy, scope ubyte[] scanlineScratch,
    scope ubyte[] zlibScratch, scope ubyte[] encoded)
    @safe pure nothrow @nogc
{
    HashChainMatchFinder finder;
    return borrowedHashWrite(shape, pixels, rowStride, lossPolicy,
        scanlineScratch, zlibScratch, encoded, finder);
}

/// Row-bounded decode keeps only the current and preceding unfiltered row.
Result borrowedRowRead(scope const(ubyte)[] encoded, scope ubyte[] row,
    scope ubyte[] previous, scope ubyte[] pixels, size_t rowStride,
    ref InflateWorkspace decoder) @safe pure nothrow @nogc
{
    return decodePngRows(encoded, row, previous, pixels, rowStride, decoder);
}

/// Pull-style writer accepts exactly one already-selected technical row.
Result borrowedRowWrite(ref StoredRowWriter writer, scope const(ubyte)[] row,
    scope ubyte[] scratch, scope ubyte[] chunkOutput)
    @safe pure nothrow @nogc
{
    return writeStoredRow(writer, row, scratch, chunkOutput);
}
