module png_oracle;

import std.file : read, write;
import std.path : buildPath;
import png_research;
import compression.deflate : InflateWorkspace;
import compression.encode : HashChainMatchFinder;
import compression.checksum : crc32;

private uint be32(const(ubyte)[] data, size_t p)
{
    return (cast(uint)data[p] << 24) | (cast(uint)data[p + 1] << 16) |
        (cast(uint)data[p + 2] << 8) | data[p + 3];
}

private void put32(ubyte[] data, size_t p, uint v)
{
    data[p] = cast(ubyte)(v >> 24); data[p + 1] = cast(ubyte)(v >> 16);
    data[p + 2] = cast(ubyte)(v >> 8); data[p + 3] = cast(ubyte)v;
}

void main(string[] args)
{
    if (args.length == 3 && args[1] == "negative")
    {
        const folder = args[2];
        assert(inspectPng(cast(ubyte[])read(buildPath(folder, "bad-crc.png"))).status == Status.badCrc);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder, "bad-order.png"))).status == Status.invalidChunkOrder);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder, "indexed.png"))).ok);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder, "unknown-critical.png"))).status == Status.unsupported);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder, "apng-marker.png"))).status == Status.unsupported);
        auto trns = cast(ubyte[])read(buildPath(folder, "trns.png"));
        auto trnsInfo = inspectPng(trns[]);
        assert(trnsInfo.ok && trnsInfo.info.hasTransparency &&
            trnsInfo.info.transparencyBytes == 2);
        ubyte[2] trnsBytes;
        assert(readPngPaletteAndTransparency(trns[], null, trnsBytes[]).ok);
        assert(trnsBytes[] == [0, 0]);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder,
            "indexed-missing-plte.png"))).status == Status.invalidChunkOrder);
        assert(inspectPng(cast(ubyte[])read(buildPath(folder,
            "indexed-bad-trns.png"))).status == Status.invalidInput);
        auto outOfRange = cast(ubyte[])read(buildPath(folder,
            "indexed-out-of-range.png"));
        auto outOfRangeInfo = inspectPng(outOfRange[]);
        assert(outOfRangeInfo.ok);
        ubyte[32] badCompressed, badFiltered, badPixels;
        badPixels[] = 0xa5;
        InflateWorkspace badWorkspace;
        assert(decodePng(outOfRange[], badCompressed[], badFiltered[],
            badPixels[], outOfRangeInfo.info.rowBytes, badWorkspace).status ==
            Status.invalidInput);
        foreach (b; badPixels) assert(b == 0xa5);
        auto bad = cast(ubyte[])read(buildPath(folder, "bad-filter.png"));
        auto info = inspectPng(bad[]);
        assert(info.ok);
        auto compressed = new ubyte[info.info.compressedBytes];
        auto filtered = new ubyte[info.info.filteredBytes];
        auto destination = new ubyte[info.info.rowBytes * info.info.height];
        destination[] = 0xa5;
        InflateWorkspace decoder;
        assert(decodePng(bad[], compressed[], filtered[], destination[],
            info.info.rowBytes, decoder).status == Status.invalidFilter);
        foreach (b; destination) assert(b == 0xa5);
        ubyte[] row = new ubyte[info.info.rowBytes + 1];
        ubyte[] previous = new ubyte[info.info.rowBytes];
        auto streamedBad = decodePngRows(bad[], row[], previous[], destination[],
            info.info.rowBytes, decoder);
        assert(streamedBad.status == Status.invalidFilter && streamedBad.written == 0);
        foreach (b; destination) assert(b == 0xa5);
        auto badAdler = cast(ubyte[])read(buildPath(folder, "bad-adler.png"));
        assert(inspectPng(badAdler[]).ok);
        assert(decodePng(badAdler[], compressed[], filtered[], destination[],
            info.info.rowBytes, decoder).status == Status.codecError);
        foreach (b; destination) assert(b == 0xa5);
        auto partial = decodePngRows(badAdler[], row[], previous[], destination[],
            info.info.rowBytes, decoder);
        assert(partial.status == Status.codecError &&
            partial.written == cast(size_t)info.info.height * info.info.rowBytes);
        // A row larger than one RFC 1951 stored block must split cleanly.
        Info wide;
        wide.width = 70_000; wide.height = 1;
        wide.bitDepth = 8; wide.colorType = 0;
        auto wideReq = storedRowRequirements(wide.width, wide.height,
            wide.bitDepth, wide.colorType);
        assert(wideReq.status == Status.ok);
        auto widePixels = new ubyte[wide.width];
        foreach (size_t i; 0 .. widePixels.length)
            widePixels[i] = cast(ubyte)(i * 17);
        auto wideRow = new ubyte[wideReq.filteredBytes];
        auto wideChunk = new ubyte[wideReq.pngCapacity];
        StoredRowWriter wideWriter;
        assert(beginStoredRowWriter(wideWriter, wide,
            MetadataPolicy.rejectLoss) == Status.ok);
        auto widePart = writeStoredRow(wideWriter, widePixels[], wideRow[],
            wideChunk[]);
        assert(widePart.ok && wideWriter.done);
        auto wideInfo = inspectPng(wideChunk[0 .. widePart.written]);
        assert(wideInfo.ok);
        auto wideFiltered = new ubyte[wideInfo.info.filteredBytes];
        auto wideCompressed = new ubyte[wideInfo.info.compressedBytes];
        auto wideDecoded = new ubyte[widePixels.length];
        assert(decodePng(wideChunk[0 .. widePart.written], wideCompressed[],
            wideFiltered[], wideDecoded[], wideInfo.info.rowBytes,
            badWorkspace).ok);
        assert(wideDecoded[] == widePixels[]);

        auto rgb = cast(ubyte[])read(buildPath(folder, "rgb8.png"));
        auto rgbInfo = inspectPng(rgb[]);
        assert(rgbInfo.ok && rgbInfo.info.hasAncillary);
        auto rgbPixels = cast(ubyte[])read(buildPath(folder, "rgb8.raw"));
        auto rgbReq = writeRequirements(rgbInfo.info.width, rgbInfo.info.height,
            rgbInfo.info.bitDepth, rgbInfo.info.colorType);
        auto rgbFiltered = new ubyte[rgbReq.filteredBytes];
        auto rgbZlib = new ubyte[rgbReq.zlibCapacity];
        auto rgbBase = new ubyte[rgbReq.pngCapacity];
        auto rgbOutput = new ubyte[rgbReq.pngCapacity + rgb.length];
        rgbOutput[] = 0xa5;
        auto unsafe = cast(ubyte[])read(buildPath(folder, "metadata-unsafe.png"));
        assert(inspectPng(unsafe[]).ok);
        assert(encodePngWithMetadata(unsafe[], rgbInfo.info, rgbPixels[],
            rgbInfo.info.rowBytes, MetadataTransfer(false, false),
            rgbFiltered[], rgbZlib[], rgbBase[], rgbOutput[]).status ==
            Status.metadataWouldBeLost);
        foreach (b; rgbOutput) assert(b == 0xa5);
        auto dropped = encodePngWithMetadata(unsafe[], rgbInfo.info, rgbPixels[],
            rgbInfo.info.rowBytes, MetadataTransfer(false, true),
            rgbFiltered[], rgbZlib[], rgbBase[], rgbOutput[]);
        assert(dropped.ok && dropped.metadataDropped);
        write(buildPath(folder, "metadata-unsafe-dropped.png"),
            rgbOutput[0 .. dropped.written]);
        auto color = cast(ubyte[])read(buildPath(folder, "metadata-color.png"));
        assert(encodePngWithMetadata(color[], rgbInfo.info, rgbPixels[],
            rgbInfo.info.rowBytes, MetadataTransfer(false, false),
            rgbFiltered[], rgbZlib[], rgbBase[], rgbOutput[]).status ==
            Status.metadataWouldBeLost);
        auto keptColor = encodePngWithMetadata(color[], rgbInfo.info, rgbPixels[],
            rgbInfo.info.rowBytes, MetadataTransfer(true, false),
            rgbFiltered[], rgbZlib[], rgbBase[], rgbOutput[]);
        assert(keptColor.ok && !keptColor.metadataDropped);
        write(buildPath(folder, "metadata-color-kept.png"),
            rgbOutput[0 .. keptColor.written]);
        return;
    }
    if (args.length == 4 && args[1] == "read-only")
    {
        auto file = cast(ubyte[])read(args[2]);
        auto expected = cast(ubyte[])read(args[3]);
        auto inspected = inspectPng(file[]);
        assert(inspected.ok);
        auto info = inspected.info;
        assert(expected.length == cast(size_t)info.height * info.rowBytes);
        auto compressed = new ubyte[info.compressedBytes];
        auto filtered = new ubyte[info.filteredBytes];
        auto pixels = new ubyte[expected.length];
        InflateWorkspace decoder;
        assert(decodePng(file[], compressed[], filtered[], pixels[],
            info.rowBytes, decoder).ok);
        assert(pixels[] == expected[]);
        auto row = new ubyte[info.rowBytes + 1];
        auto previous = new ubyte[info.rowBytes];
        pixels[] = 0;
        assert(decodePngRows(file[], row[], previous[], pixels[],
            info.rowBytes, decoder).ok);
        assert(pixels[] == expected[]);
        auto palette = new ubyte[info.paletteEntries * 3];
        auto transparency = new ubyte[info.transparencyBytes];
        assert(readPngPaletteAndTransparency(file[], palette[], transparency[]).ok);
        if (info.colorType == 3)
        {
            assert(info.paletteEntries == (1U << info.bitDepth));
            assert(info.transparencyBytes == info.paletteEntries);
            foreach (size_t i; 0 .. info.paletteEntries)
            {
                assert(palette[i * 3] == cast(ubyte)(i * 17));
                assert(transparency[i] == cast(ubyte)(255 - i * 13));
            }
        }
        assert(writeRequirements(info.width, info.height, info.bitDepth,
            info.colorType).status == Status.unsupported);
        return;
    }
    assert(args.length == 4);
    auto file = cast(ubyte[])read(args[1]);
    auto expected = cast(ubyte[])read(args[2]);
    const inspected = inspectPng(file[]);
    assert(inspected.ok);
    const info = inspected.info;
    if (info.hasTransparency)
    {
        auto palette = new ubyte[info.paletteEntries * 3];
        auto transparency = new ubyte[info.transparencyBytes];
        auto extracted = readPngPaletteAndTransparency(file[], palette[],
            transparency[]);
        assert(extracted.ok && extracted.written ==
            cast(size_t)info.paletteEntries * 3 + info.transparencyBytes);
    }
    assert(expected.length == cast(size_t)info.height * info.rowBytes);
    auto compressed = new ubyte[info.compressedBytes];
    auto filtered = new ubyte[info.filteredBytes];
    const rowStride = info.rowBytes + 5;
    auto pixels = new ubyte[rowStride * info.height];
    pixels[] = 0xa5;
    InflateWorkspace decoder;
    auto decoded = decodePng(file[], compressed[], filtered[], pixels[],
        rowStride, decoder);
    assert(decoded.ok && decoded.written == expected.length);
    foreach (size_t y; 0 .. info.height)
    {
        assert(pixels[y * rowStride .. y * rowStride + info.rowBytes] ==
            expected[y * info.rowBytes .. (y + 1) * info.rowBytes]);
        foreach (b; pixels[y * rowStride + info.rowBytes .. (y + 1) * rowStride])
            assert(b == 0xa5);
    }
    auto row = new ubyte[info.rowBytes + 1];
    auto previous = new ubyte[info.rowBytes];
    pixels[] = 0xa5;
    auto streamed = decodePngRows(file[], row[], previous[], pixels[], rowStride,
        decoder);
    assert(streamed.ok && streamed.written == expected.length);
    foreach (size_t y; 0 .. info.height)
    {
        assert(pixels[y * rowStride .. y * rowStride + info.rowBytes] ==
            expected[y * info.rowBytes .. (y + 1) * info.rowBytes]);
        foreach (b; pixels[y * rowStride + info.rowBytes .. (y + 1) * rowStride])
            assert(b == 0xa5);
    }
    pixels[] = 0xa5;
    assert(decodePngRows(file[], row[][0 .. $ - 1], previous[], pixels[],
        rowStride, decoder).status == Status.workspaceTooSmall);
    foreach (b; pixels) assert(b == 0xa5);
    // Failure preflight leaves caller-visible pixels intact.
    pixels[] = 0xa5;
    assert(decodePng(file[], compressed[][0 .. $ - 1], filtered[], pixels[],
        rowStride, decoder).status == Status.workspaceTooSmall);
    foreach (b; pixels) assert(b == 0xa5);
    assert(decodePng(file[], compressed[], filtered[], pixels[][0 .. 0],
        rowStride, decoder).status == Status.destinationTooSmall);
    foreach (b; pixels) assert(b == 0xa5);
    assert(inspectPng(file[0 .. $ - 1]).status == Status.truncated);
    assert(inspectPng(file[], Limits(0)).status == Status.sizeLimit);
    auto tightLimits = Limits.init;
    tightLimits.maxFileBytes = file.length - 1;
    assert(inspectPng(file[], tightLimits).status == Status.sizeLimit);
    if (info.hasAncillary)
    {
        tightLimits = Limits.init;
        tightLimits.maxAncillaryBytes = 0;
        assert(inspectPng(file[], tightLimits).status == Status.sizeLimit);
    }
    auto changed = file.dup;
    changed[0] ^= 1;
    assert(inspectPng(changed[]).status == Status.invalidInput);
    changed = file.dup;
    changed[28] = 1; // unsupported Adam7 variant, with valid IHDR CRC
    put32(changed[], 29, crc32(changed[12 .. 29]));
    assert(inspectPng(changed[]).status == Status.unsupported);
    size_t idat;
    for (size_t p = 8; p < file.length; p += 12 + be32(file[], p))
        if (file[p + 4 .. p + 8] == "IDAT") { idat = p; break; }
    assert(idat != 0 && be32(file[], idat) > 0);
    changed = file.dup;
    changed[idat + 8] ^= 1;
    assert(inspectPng(changed[]).status == Status.badCrc);
    assert(decodePng(changed[], compressed[], filtered[], pixels[],
        rowStride, decoder).status == Status.badCrc);
    foreach (b; pixels) assert(b == 0xa5);
    put32(changed[], idat + 8 + be32(changed[], idat),
        crc32(changed[idat + 4 .. idat + 8 + be32(changed[], idat)]));
    assert(inspectPng(changed[]).ok);
    assert(decodePng(changed[], compressed[], filtered[], pixels[],
        rowStride, decoder).status == Status.codecError);
    foreach (b; pixels) assert(b == 0xa5);

    const req = writeRequirements(info.width, info.height, info.bitDepth,
        info.colorType);
    assert(req.status == Status.ok);
    auto encodeScratch = new ubyte[req.filteredBytes];
    auto zlibScratch = new ubyte[req.zlibCapacity];
    auto output = new ubyte[req.pngCapacity];
    output[] = 0xa5;
    if (info.hasAncillary)
    {
        assert(encodePng(info, pixels[], rowStride, MetadataPolicy.rejectLoss,
            encodeScratch[], zlibScratch[], output[]).status == Status.metadataWouldBeLost);
        foreach (b; output) assert(b == 0xa5);
    }
    // Restore pixels after the negative tests and encode with explicit loss.
    foreach (size_t y; 0 .. info.height)
        pixels[y * rowStride .. y * rowStride + info.rowBytes] =
            expected[y * info.rowBytes .. (y + 1) * info.rowBytes];
    assert(encodePng(info, pixels[], rowStride, MetadataPolicy.drop,
        encodeScratch[], zlibScratch[], output[][0 .. $ - 1]).status ==
        Status.destinationTooSmall);
    foreach (b; output) assert(b == 0xa5);
    auto encoded = encodePng(info, pixels[], rowStride, MetadataPolicy.drop,
        encodeScratch[], zlibScratch[], output[]);
    assert(encoded.ok && encoded.metadataDropped == info.hasAncillary);
    assert(inspectPng(output[0 .. encoded.written]).ok);
    write(args[3], output[0 .. encoded.written]);
    auto adaptive = encodePng(info, pixels[], rowStride, MetadataPolicy.drop,
        encodeScratch[], zlibScratch[], output[], Limits.init,
        FilterStrategy.adaptive);
    assert(adaptive.ok && inspectPng(output[0 .. adaptive.written]).ok);
    write(args[3][0 .. $ - 4] ~ "-adaptive.png", output[0 .. adaptive.written]);
    HashChainMatchFinder hashFinder;
    output[] = 0xa5;
    assert(encodePngHashChain(info, pixels[], rowStride, MetadataPolicy.drop,
        encodeScratch[], zlibScratch[], output[][0 .. $ - 1], hashFinder).status ==
        Status.destinationTooSmall);
    foreach (value; output) assert(value == 0xa5);
    auto fast = encodePngHashChain(info, pixels[], rowStride,
        MetadataPolicy.drop, encodeScratch[], zlibScratch[], output[],
        hashFinder);
    assert(fast.ok && inspectPng(output[0 .. fast.written]).ok);
    write(args[3][0 .. $ - 4] ~ "-fast.png", output[0 .. fast.written]);
    if (info.hasAncillary && !info.hasTransparency)
    {
        auto base = new ubyte[req.pngCapacity];
        auto retained = new ubyte[req.pngCapacity + file.length];
        retained[] = 0xa5;
        auto status = encodePngWithMetadata(file[], info, pixels[], rowStride,
            MetadataTransfer(false, false), encodeScratch[], zlibScratch[],
            base[], retained[][0 .. 1]);
        assert(status.status == Status.destinationTooSmall);
        foreach (b; retained) assert(b == 0xa5);
        auto withMetadata = encodePngWithMetadataHashChain(file[], info, pixels[],
            rowStride, MetadataTransfer(false, false), encodeScratch[],
            zlibScratch[], base[], retained[], hashFinder);
        assert(withMetadata.ok && !withMetadata.metadataDropped);
        assert(inspectPng(retained[0 .. withMetadata.written]).ok);
        write(args[3][0 .. $ - 4] ~ "-metadata.png",
            retained[0 .. withMetadata.written]);
    }
    const storedReq = storedRowRequirements(info.width, info.height,
        info.bitDepth, info.colorType);
    assert(storedReq.status == Status.ok);
    auto storedRow = new ubyte[storedReq.filteredBytes];
    auto storedOutput = new ubyte[storedReq.pngCapacity];
    storedOutput[] = 0xa5;
    assert(encodePngRowsStored(info, pixels[], rowStride, MetadataPolicy.drop,
        storedRow[][0 .. $ - 1], storedOutput[]).status == Status.workspaceTooSmall);
    foreach (b; storedOutput) assert(b == 0xa5);
    assert(encodePngRowsStored(info, pixels[], rowStride, MetadataPolicy.drop,
        storedRow[], storedOutput[][0 .. $ - 1]).status == Status.destinationTooSmall);
    foreach (b; storedOutput) assert(b == 0xa5);
    auto stored = encodePngRowsStored(info, pixels[], rowStride, MetadataPolicy.drop,
        storedRow[], storedOutput[]);
    assert(stored.ok && stored.written == storedReq.pngCapacity);
    assert(inspectPng(storedOutput[0 .. stored.written]).ok);
    const storedName = args[3][0 .. $ - 4] ~ "-stored.png";
    write(storedName, storedOutput[0 .. stored.written]);
    StoredRowWriter writer;
    assert(beginStoredRowWriter(writer, info, MetadataPolicy.drop) == Status.ok);
    auto chunkOutput = new ubyte[storedRowChunkCapacity(info)];
    ubyte[] assembled;
    foreach (size_t y; 0 .. info.height)
    {
        auto visibleRow = pixels[y * rowStride .. y * rowStride + info.rowBytes];
        assert(writeStoredRow(writer, visibleRow, storedRow[],
            chunkOutput[][0 .. 1]).status == Status.destinationTooSmall);
        auto part = writeStoredRow(writer, visibleRow, storedRow[], chunkOutput[]);
        assert(part.ok && part.metadataDropped == info.hasAncillary);
        assembled ~= chunkOutput[0 .. part.written];
    }
    assert(writer.done && inspectPng(assembled[]).ok);
    write(args[3][0 .. $ - 4] ~ "-row-stream.png", assembled[]);
}
