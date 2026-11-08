/** BigTIFF tiled writer using TIFF LZW compression (Compression=5). */
module imageio.tiff_lzw_write;

import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, mapSinkFailure;
import imageio.tiff_tile_write : TiffTileWriteInfo;

private void p16(scope ubyte[] b, size_t p, ushort v) @safe pure nothrow @nogc
{ b[p] = cast(ubyte)v; b[p + 1] = cast(ubyte)(v >> 8); }
private void p64(scope ubyte[] b, size_t p, ulong v) @safe pure nothrow @nogc
{ foreach (size_t i; 0 .. 8) b[p + i] = cast(ubyte)(v >> (i * 8)); }
private void e(scope ubyte[] b, ref size_t p, ushort tag, ushort type,
    ulong count, ulong value) @safe pure nothrow @nogc
{ p16(b,p,tag); p16(b,p+2,type); p64(b,p+4,count); p64(b,p+12,value); p += 20; }

private size_t lzwLiteral(scope const(ubyte)[] input, scope ubyte[] output)
@safe pure nothrow @nogc
{
    size_t p; ulong bits; uint bitCount; size_t literals;
    void put(uint code, uint width) @safe pure nothrow @nogc
    {
        bits = (bits << width) | code; bitCount += width;
        while (bitCount >= 8)
        { bitCount -= 8; output[p++] = cast(ubyte)(bits >> bitCount); bits &= (1UL << bitCount) - 1; }
    }
    put(256, 9);
    foreach (ubyte value; input)
    {
        if (literals == 200) { put(256, 9); literals = 0; }
        put(value, 9); ++literals;
    }
    put(257, 9);
    if (bitCount != 0) output[p++] = cast(ubyte)(bits << (8 - bitCount));
    return p;
}

/** Write chunky UInt8/UInt16 BigTIFF tiles compressed with literal-safe LZW. */
ImageWriteResult writeBigTiffLzwTiles(ByteSink sink, TiffTileWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    if (info.width == 0 || info.height == 0 || info.tileWidth == 0 || info.tileLength == 0
        || info.channels < 1 || info.channels > 4 || (info.sampleBytes != 1 && info.sampleBytes != 2))
        return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    const pixelBytes = cast(size_t)info.channels * info.sampleBytes, rowBytes = cast(size_t)info.width * pixelBytes;
    if (rowStride < rowBytes || cast(size_t)(info.height - 1) * rowStride + rowBytes > source.length)
        return ImageWriteResult(ImageWriteError.truncatedInput);
    const across = (info.width + info.tileWidth - 1) / info.tileWidth, down = (info.height + info.tileLength - 1) / info.tileLength;
    const tiles = cast(size_t)across * down, rawBytes = cast(size_t)info.tileWidth * info.tileLength * pixelBytes;
    if (rawBytes > (size_t.max - 64) / 2) return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto compressed = new ubyte[][](tiles); size_t compressedBytes;
    foreach (size_t n; 0 .. tiles)
    {
        auto raw = new ubyte[](rawBytes); const ty=n/across, tx=n%across;
        foreach (size_t y; 0 .. info.tileLength)
        { const sy=ty*info.tileLength+y; if (sy>=info.height) break; const sx=tx*info.tileWidth;
          const cp=sx+info.tileWidth>info.width?info.width-sx:info.tileWidth;
          raw[y*info.tileWidth*pixelBytes .. y*info.tileWidth*pixelBytes+cp*pixelBytes]=
              source[sy*rowStride+sx*pixelBytes .. sy*rowStride+(sx+cp)*pixelBytes]; }
        auto encoded = new ubyte[](rawBytes * 2 + 64); const produced=lzwLiteral(raw[],encoded[]);
        compressed[n]=encoded[0..produced].dup;
        if (compressedBytes > size_t.max-produced) return ImageWriteResult(ImageWriteError.outputLimitExceeded);
        compressedBytes += produced;
    }
    const entries=11U, ifdEnd=16+8+entries*20+8, offsets=ifdEnd, counts=offsets+tiles*8, pixels=counts+tiles*8;
    if (pixels>options.maximumOutputBytes || compressedBytes>size_t.max-pixels || pixels+compressedBytes>options.maximumOutputBytes)
        return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto buf=new ubyte[](pixels+compressedBytes); buf[0]='I'; buf[1]='I'; p16(buf,2,43); p16(buf,4,8); p16(buf,6,0); p64(buf,8,16); p64(buf,16,entries);
    size_t p=24; const bits=info.sampleBytes*8; ulong bitsValue; foreach(size_t i;0..info.channels) bitsValue|=cast(ulong)bits<<(i*16);
    e(buf,p,256,16,1,info.width); e(buf,p,257,16,1,info.height); e(buf,p,258,3,info.channels,bitsValue); e(buf,p,259,3,1,5);
    e(buf,p,262,3,1,info.channels<=2?1:2); e(buf,p,277,3,1,info.channels); e(buf,p,284,3,1,1); e(buf,p,322,16,1,info.tileWidth); e(buf,p,323,16,1,info.tileLength); e(buf,p,324,16,tiles,offsets); e(buf,p,325,16,tiles,counts); p64(buf,p,0);
    size_t data=pixels; foreach(size_t n;0..tiles){p64(buf,offsets+n*8,data);p64(buf,counts+n*8,compressed[n].length);buf[data..data+compressed[n].length]=compressed[n][];data+=compressed[n].length;}
    auto w=sink.write(buf[]); if(w.hasError)return mapSinkFailure(w.error().bytesWritten,w.error().kind); if(w.value().bytesWritten!=buf.length)return ImageWriteResult(ImageWriteError.sinkFailure,w.value().bytesWritten);
    return ImageWriteResult(ImageWriteError.none,buf.length,MetadataDisposition.notApplicable);
}
