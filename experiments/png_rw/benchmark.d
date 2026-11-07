/// Separate reproducible baseline; not a format-admission benchmark.
module png_benchmark;

import std.datetime.stopwatch : StopWatch;
import std.file : read;
import std.stdio : writefln;
import std.conv : to;
import png_research;
import compression.deflate : InflateWorkspace;
import compression.checksum : crc32;
import compression.encode : encodeZlibStored, HashChainMatchFinder;
import compression.core : DecodeStatus;

void main(string[] args)
{
    if (args.length != 3) throw new Exception("usage: benchmark image.png iterations");
    const iterations = to!uint(args[2]);
    if (!iterations) throw new Exception("iterations must be positive");
    auto file = cast(ubyte[])read(args[1]);
    auto parsed = inspectPng(file[]);
    if (!parsed.ok) throw new Exception("PNG inspection failed");
    auto info = parsed.info;
    auto compressed = new ubyte[info.compressedBytes];
    auto filtered = new ubyte[info.filteredBytes];
    auto pixels = new ubyte[info.rowBytes * info.height];
    auto decodeRow = new ubyte[info.rowBytes + 1];
    auto previousRow = new ubyte[info.rowBytes];
    InflateWorkspace decoder;
    auto req = writeRequirements(info.width, info.height, info.bitDepth, info.colorType);
    if (req.status != Status.ok) throw new Exception("write requirements failed");
    auto encodeScratch = new ubyte[req.filteredBytes];
    auto zlibScratch = new ubyte[req.zlibCapacity];
    auto encoded = new ubyte[req.pngCapacity];
    HashChainMatchFinder hashFinder;
    auto storedReq = storedRowRequirements(info.width, info.height,
        info.bitDepth, info.colorType);
    if (storedReq.status != Status.ok) throw new Exception("stored requirements failed");
    auto rowScratch = new ubyte[storedReq.filteredBytes];
    auto storedOutput = new ubyte[storedReq.pngCapacity];
    auto chunkOutput = new ubyte[storedRowChunkCapacity(info)];
    auto warmRead = decodePng(file[], compressed[], filtered[], pixels[],
        info.rowBytes, decoder);
    if (!warmRead.ok) throw new Exception("warm decode failed");
    auto warmWrite = encodePng(info, pixels[], info.rowBytes, MetadataPolicy.drop,
        encodeScratch[], zlibScratch[], encoded[]);
    if (!warmWrite.ok) throw new Exception("warm encode failed");
    auto warmAdaptive = encodePng(info, pixels[], info.rowBytes,
        MetadataPolicy.drop, encodeScratch[], zlibScratch[], encoded[],
        Limits.init, FilterStrategy.adaptive);
    if (!warmAdaptive.ok) throw new Exception("warm adaptive encode failed");
    auto warmFast = encodePngHashChain(info, pixels[], info.rowBytes,
        MetadataPolicy.drop, encodeScratch[], zlibScratch[], encoded[],
        hashFinder);
    if (!warmFast.ok) throw new Exception("warm fast encode failed");
    auto warmStored = encodePngRowsStored(info, pixels[], info.rowBytes,
        MetadataPolicy.drop, rowScratch[], storedOutput[]);
    if (!warmStored.ok) throw new Exception("warm stored encode failed");

    StopWatch watch;
    uint checksum;
    watch.start();
    foreach (_; 0 .. iterations)
    {
        auto result = decodePng(file[], compressed[], filtered[], pixels[],
            info.rowBytes, decoder);
        if (!result.ok) throw new Exception("decode failed");
        checksum ^= crc32(pixels[]);
    }
    auto decodeUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    foreach (_; 0 .. iterations)
    {
        auto result = decodePngRows(file[], decodeRow[], previousRow[], pixels[],
            info.rowBytes, decoder);
        if (!result.ok) throw new Exception("row decode failed");
        checksum ^= crc32(pixels[]);
    }
    auto rowDecodeUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    size_t bytesWritten;
    foreach (_; 0 .. iterations)
    {
        auto result = encodePng(info, pixels[], info.rowBytes, MetadataPolicy.drop,
            encodeScratch[], zlibScratch[], encoded[]);
        if (!result.ok) throw new Exception("encode failed");
        bytesWritten = result.written;
        checksum ^= crc32(encoded[0 .. bytesWritten]);
    }
    auto encodeUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    size_t adaptiveBytes;
    foreach (_; 0 .. iterations)
    {
        auto result = encodePng(info, pixels[], info.rowBytes,
            MetadataPolicy.drop, encodeScratch[], zlibScratch[], encoded[],
            Limits.init, FilterStrategy.adaptive);
        if (!result.ok) throw new Exception("adaptive encode failed");
        adaptiveBytes = result.written;
        checksum ^= crc32(encoded[0 .. adaptiveBytes]);
    }
    auto adaptiveUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    size_t fastBytes;
    foreach (_; 0 .. iterations)
    {
        auto result = encodePngHashChain(info, pixels[], info.rowBytes,
            MetadataPolicy.drop, encodeScratch[], zlibScratch[], encoded[],
            hashFinder);
        if (!result.ok) throw new Exception("fast encode failed");
        fastBytes = result.written;
        checksum ^= crc32(encoded[0 .. fastBytes]);
    }
    auto fastUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    size_t storedBytes;
    foreach (_; 0 .. iterations)
    {
        auto result = encodePngRowsStored(info, pixels[], info.rowBytes,
            MetadataPolicy.drop, rowScratch[], storedOutput[]);
        if (!result.ok) throw new Exception("stored encode failed");
        storedBytes = result.written;
        checksum ^= crc32(storedOutput[0 .. storedBytes]);
    }
    auto storedUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    size_t rowWriterBytes;
    foreach (_; 0 .. iterations)
    {
        StoredRowWriter writer;
        if (beginStoredRowWriter(writer, info, MetadataPolicy.drop) != Status.ok)
            throw new Exception("row writer initialization failed");
        size_t total;
        foreach (size_t y; 0 .. info.height)
        {
            auto part = writeStoredRow(writer,
                pixels[y * info.rowBytes .. (y + 1) * info.rowBytes],
                rowScratch[], chunkOutput[]);
            if (!part.ok) throw new Exception("row writer failed");
            total += part.written;
            checksum ^= crc32(chunkOutput[0 .. part.written]);
        }
        rowWriterBytes = total;
    }
    auto rowWriterUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    foreach (_; 0 .. iterations)
    {
        foreach (size_t y; 0 .. info.height)
        {
            const p = y * (info.rowBytes + 1);
            encodeScratch[p] = 0;
            encodeScratch[p + 1 .. p + 1 + info.rowBytes] =
                pixels[y * info.rowBytes .. (y + 1) * info.rowBytes];
        }
        checksum ^= crc32(encodeScratch[]);
    }
    auto filterUs = watch.peek.total!"usecs";
    watch.reset(); watch.start();
    foreach (_; 0 .. iterations)
    {
        auto result = encodeZlibStored(encodeScratch[], zlibScratch[]);
        if (result.status != DecodeStatus.done) throw new Exception("zlib encode failed");
        checksum ^= crc32(zlibScratch[0 .. result.produced]);
    }
    auto deflateUs = watch.peek.total!"usecs";
    writefln("width=%s height=%s bands=%s depth=%s iterations=%s input_bytes=%s output_bytes=%s adaptive_bytes=%s fast_bytes=%s stored_bytes=%s row_writer_bytes=%s decode_us=%s row_decode_us=%s encode_us=%s adaptive_us=%s fast_us=%s stored_us=%s row_writer_us=%s filter_us=%s deflate_us=%s full_decode_scratch=%s row_decode_scratch=%s full_encode_scratch=%s fast_hash_scratch=%s stored_encode_scratch=%s row_writer_state=%s checksum=%s",
        info.width, info.height, info.channels, info.bitDepth, iterations,
        file.length, bytesWritten, adaptiveBytes, fastBytes, storedBytes, rowWriterBytes,
        decodeUs, rowDecodeUs, encodeUs, adaptiveUs, fastUs, storedUs, rowWriterUs,
        filterUs, deflateUs, compressed.length + filtered.length,
        info.rowBytes * 2 + 1, encodeScratch.length + zlibScratch.length,
        HashChainMatchFinder.sizeof,
        rowScratch.length, StoredRowWriter.sizeof, checksum);
}
