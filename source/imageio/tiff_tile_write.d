/** BigTIFF writer for uncompressed chunky UInt8/UInt16 tiles. */
module imageio.tiff_tile_write;

import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, mapSinkFailure;

struct TiffTileWriteInfo
{
    uint width, height, tileWidth, tileLength;
    ubyte channels, sampleBytes;
}

private void p16(scope ubyte[] b, size_t p, ushort v)
@safe pure nothrow @nogc { b[p] = cast(ubyte)v; b[p + 1] = cast(ubyte)(v >> 8); }
private void p64(scope ubyte[] b, size_t p, ulong v)
@safe pure nothrow @nogc { foreach (size_t i; 0 .. 8) b[p + i] = cast(ubyte)(v >> (i * 8)); }
private void e(scope ubyte[] b, ref size_t p, ushort tag, ushort type,
    ulong count, ulong value) @safe pure nothrow @nogc
{ p16(b,p,tag); p16(b,p+2,type); p64(b,p+4,count); p64(b,p+12,value); p += 20; }

ImageWriteResult writeBigTiffTiles(ByteSink sink, TiffTileWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    if (info.width == 0 || info.height == 0 || info.tileWidth == 0
        || info.tileLength == 0 || info.channels < 1 || info.channels > 4
        || (info.sampleBytes != 1 && info.sampleBytes != 2))
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    const pixelBytes = cast(size_t)info.channels * info.sampleBytes;
    const rowBytes = cast(size_t)info.width * pixelBytes;
    if (rowStride < rowBytes || cast(size_t)(info.height - 1) * rowStride
        + rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    const across = (info.width + info.tileWidth - 1) / info.tileWidth;
    const down = (info.height + info.tileLength - 1) / info.tileLength;
    const tiles = cast(size_t)across * down;
    const tileBytes = cast(size_t)info.tileWidth * info.tileLength * pixelBytes;
    const entries = 11U;
    const ifdEnd = 16 + 8 + entries * 20 + 8;
    const offsets = ifdEnd;
    const counts = offsets + tiles * 8;
    const pixels = counts + tiles * 8;
    if (pixels > options.maximumOutputBytes
        || tileBytes > size_t.max / tiles
        || pixels + tileBytes * tiles > options.maximumOutputBytes)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto buf = new ubyte[](pixels + tileBytes * tiles);
    buf[0]='I'; buf[1]='I'; p16(buf,2,43); p16(buf,4,8); p16(buf,6,0); p64(buf,8,16);
    p64(buf,16,entries); size_t p=24; const bits=info.sampleBytes*8;
    ulong bitsValue; foreach (size_t i; 0 .. info.channels) bitsValue |= cast(ulong)bits << (i*16);
    e(buf,p,256,16,1,info.width); e(buf,p,257,16,1,info.height);
    e(buf,p,258,3,info.channels,bitsValue); e(buf,p,259,3,1,1);
    e(buf,p,262,3,1,info.channels <= 2 ? 1 : 2);
    e(buf,p,277,3,1,info.channels); e(buf,p,284,3,1,1);
    e(buf,p,322,16,1,info.tileWidth); e(buf,p,323,16,1,info.tileLength);
    e(buf,p,324,16,tiles,offsets); e(buf,p,325,16,tiles,counts);
    p64(buf,p,0);
    foreach (size_t ty; 0 .. down) foreach (size_t tx; 0 .. across)
    {
        const n = ty * across + tx;
        const off = pixels + n * tileBytes;
        p64(buf, offsets + n*8, off);
        p64(buf, counts + n*8, tileBytes);
        foreach (size_t y; 0 .. info.tileLength)
        {
            const sy = ty * info.tileLength + y;
            if (sy >= info.height) break;
            const sx = tx * info.tileWidth;
            const copyPixels = (sx + info.tileWidth > info.width)
                ? info.width - sx : info.tileWidth;
            buf[off + y * info.tileWidth * pixelBytes
                .. off + y * info.tileWidth * pixelBytes + copyPixels * pixelBytes] =
                source[sy * rowStride + sx * pixelBytes
                    .. sy * rowStride + (sx + copyPixels) * pixelBytes];
        }
    }
    auto w=sink.write(buf[]); if (w.hasError) return mapSinkFailure(w.error().bytesWritten,w.error().kind);
    if (w.value().bytesWritten != buf.length) return ImageWriteResult(ImageWriteError.sinkFailure,w.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none,buf.length,MetadataDisposition.notApplicable);
}
