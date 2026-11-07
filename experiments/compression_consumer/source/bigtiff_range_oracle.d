module bigtiff_range_oracle;

import std.file : read;
import std.stdio : File;
import bigtiff_header;
import bigtiff_range_bridge;
import deflate_bridge : ImageSpec, Layout, requirements, BridgeStatus;
import compression.deflate : InflateWorkspace;

private ubyte[] loadRange(ref File file, ulong offset, size_t length)
{
    assert(offset <= long.max);
    auto bytes = new ubyte[length];
    file.seek(cast(long)offset);
    file.rawRead(bytes);
    return bytes;
}

private ulong value(ref File file, RangeWindow ifdWindow, Directory dir,
    Entry entry, ulong index)
{
    RangeWindow external;
    auto width = entry.type == 3 ? 2U : entry.type == 4 ? 4U : 8U;
    assert(entry.count <= size_t.max / width);
    if (entry.count * width > 8)
        external = RangeWindow(entry.value, loadRange(file, entry.value,
            cast(size_t)(entry.count * width)));
    ulong result;
    assert(unsignedAtRange(ifdWindow, dir, entry, external, index, result) == Status.ok);
    return result;
}

version (BigTiffRangeOracle)
void main(string[] args)
{
    assert(args.length == 3);
    auto expected = cast(const(ubyte)[])read(args[2]);
    auto file = File(args[1], "rb");
    auto header = loadRange(file, 0, 16);
    auto parsed = parse(header[]);
    assert(parsed.status == Status.ok);
    auto countBytes = loadRange(file, parsed.firstIfd, 8);
    auto count = read64(countBytes[], 0, header[0] == 'I');
    assert(count < 1000);
    auto ifdBytes = loadRange(file, parsed.firstIfd, cast(size_t)(count * 20 + 16));
    auto dir = parseDirectoryWindow(header[], ifdBytes[], parsed.firstIfd);
    assert(dir.status == Status.ok);
    RangeWindow ifdWindow = RangeWindow(parsed.firstIfd, ifdBytes[]);
    Entry offsets, byteCounts;
    ImageSpec spec;
    spec.bands = 1; spec.sampleBytes = 1; spec.predictor = 1;
    spec.littleEndian = dir.little;
    foreach (i; 0 .. dir.count)
    {
        Entry entry;
        assert(entryAtWindow(ifdBytes[], dir, i, entry) == Status.ok);
        switch (entry.tag)
        {
            case 256: spec.width = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 257: spec.height = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 258: spec.sampleBytes = cast(uint)(value(file, ifdWindow, dir, entry, 0) / 8); break;
            case 259: assert(value(file, ifdWindow, dir, entry, 0) == 8); break;
            case 277: spec.bands = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 317: spec.predictor = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 273: case 324: offsets = entry; spec.tiled = entry.tag == 324; break;
            case 279: case 325: byteCounts = entry; break;
            case 278: spec.blockHeight = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 322: spec.blockWidth = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            case 323: spec.blockHeight = cast(uint)value(file, ifdWindow, dir, entry, 0); break;
            default: break;
        }
    }
    if (!spec.tiled) spec.blockWidth = spec.width;
    assert(spec.sampleBytes == 1 || spec.sampleBytes == 2);
    assert(offsets.count == byteCounts.count);
    auto req = requirements(spec);
    assert(req.status == BridgeStatus.ok && req.outputBytes == expected.length);
    auto blocks = new Block64[req.blockCount];
    auto windows = new RangeWindow[req.blockCount];
    foreach (i; 0 .. req.blockCount)
    {
        auto offset = value(file, ifdWindow, dir, offsets, i);
        auto bytes = value(file, ifdWindow, dir, byteCounts, i);
        assert(bytes < 1_000_000);
        blocks[i] = Block64(offset, bytes);
        windows[i] = RangeWindow(offset, loadRange(file, offset, cast(size_t)bytes));
    }
    auto output = new ubyte[req.outputBytes];
    auto scratch = new ubyte[req.scratchBytes];
    auto staging = new ubyte[req.scratchBytes];
    InflateWorkspace decoder;
    auto result = decodeDeflateRanges(blocks[], windows[], spec, decoder,
        scratch[], staging[], output[], Layout(cast(size_t)spec.width * spec.bands * spec.sampleBytes,
            spec.bands * spec.sampleBytes, spec.sampleBytes));
    assert(result.status == BridgeStatus.ok && result.blocksWritten == blocks.length);
    assert(output == expected);
    const rowBytes = cast(size_t)spec.width * spec.bands * spec.sampleBytes;
    auto padded = new ubyte[(rowBytes + 3) * spec.height];
    padded[] = 0xa5;
    result = decodeDeflateRanges(blocks[], windows[], spec, decoder,
        scratch[], staging[], padded[], Layout(rowBytes + 3,
            spec.bands * spec.sampleBytes, spec.sampleBytes));
    assert(result.status == BridgeStatus.ok);
    foreach (y; 0 .. spec.height)
    {
        assert(padded[y * (rowBytes + 3) .. y * (rowBytes + 3) + rowBytes] ==
            expected[y * rowBytes .. (y + 1) * rowBytes]);
        foreach (gap; padded[y * (rowBytes + 3) + rowBytes .. (y + 1) * (rowBytes + 3)])
            assert(gap == 0xa5);
    }
    if (windows.length > 1)
    {
        auto first = windows[0];
        windows[0] = windows[$ - 1];
        windows[$ - 1] = first;
        output[] = 0;
        result = decodeDeflateRanges(blocks[], windows[], spec, decoder,
            scratch[], staging[], output[], Layout(rowBytes,
                spec.bands * spec.sampleBytes, spec.sampleBytes));
        assert(result.status == BridgeStatus.ok && output == expected);
    }
    // Rebase all encoded windows beyond classic TIFF's 32-bit offset range.
    foreach (i; 0 .. blocks.length)
    {
        blocks[i].offset += 0x1_0000_0000UL;
        windows[i].offset += 0x1_0000_0000UL;
    }
    output[] = 0;
    result = decodeDeflateRanges(blocks[], windows[], spec, decoder,
        scratch[], staging[], output[], Layout(cast(size_t)spec.width * spec.bands * spec.sampleBytes,
            spec.bands * spec.sampleBytes, spec.sampleBytes));
    assert(result.status == BridgeStatus.ok && output == expected);
    assert(decodeDeflateRanges(blocks[], windows[], spec, decoder,
        scratch[][0 .. $ - 1], staging[], output[], Layout(cast(size_t)spec.width * spec.bands * spec.sampleBytes,
            spec.bands * spec.sampleBytes, spec.sampleBytes)).status ==
        BridgeStatus.workspaceTooSmall);
    assert(decodeDeflateRanges(blocks[], windows[], spec, decoder,
        scratch[], staging[][0 .. $ - 1], output[], Layout(rowBytes,
            spec.bands * spec.sampleBytes, spec.sampleBytes)).status ==
        BridgeStatus.workspaceTooSmall);
    output[] = 0xa5;
    assert(decodeDeflateRanges(blocks[], windows[][0 .. 0], spec, decoder,
        scratch[], staging[], output[], Layout(cast(size_t)spec.width * spec.bands * spec.sampleBytes,
            spec.bands * spec.sampleBytes, spec.sampleBytes)).status ==
        BridgeStatus.truncated);
    foreach (byteValue; output) assert(byteValue == 0xa5);
}
