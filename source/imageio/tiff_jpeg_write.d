/** BigTIFF tiled writer using baseline JPEG tiles (Compression=7). */
module imageio.tiff_jpeg_write;

import compression.jpeg : EncodeOptions, Info, Sampling, Status, encodeJpeg;
import transport : ByteSink;
import imageio.io : ImageWriteError, ImageWriteOptions, ImageWriteResult,
    MetadataDisposition, mapSinkFailure;
import imageio.tiff_tile_write : TiffTileWriteInfo;

private void p16(scope ubyte[] b, size_t p, ushort v) @safe pure nothrow @nogc
{ b[p]=cast(ubyte)v; b[p+1]=cast(ubyte)(v>>8); }
private void p64(scope ubyte[] b, size_t p, ulong v) @safe pure nothrow @nogc
{ foreach(size_t i;0..8)b[p+i]=cast(ubyte)(v>>(i*8)); }
private void e(scope ubyte[] b, ref size_t p, ushort t, ushort ty, ulong c, ulong v) @safe pure nothrow @nogc
{ p16(b,p,t);p16(b,p+2,ty);p64(b,p+4,c);p64(b,p+12,v);p+=20; }

/** Write chunky UInt8 BigTIFF tiles as independent baseline 4:4:4 JPEGs.
 * JPEG is lossy by definition; no colour or range conversion is implied.
 */
ImageWriteResult writeBigTiffJpegTiles(ByteSink sink, TiffTileWriteInfo info,
    scope const(ubyte)[] source, size_t rowStride,
    ImageWriteOptions options = ImageWriteOptions.init) @safe
{
    if(info.width==0||info.height==0||info.tileWidth==0||info.tileLength==0||info.sampleBytes!=1
        ||(info.channels!=1&&info.channels!=3))return ImageWriteResult(ImageWriteError.unsupportedRepresentation);
    const pixelBytes=cast(size_t)info.channels, rowBytes=cast(size_t)info.width*pixelBytes;
    if(rowStride<rowBytes||cast(size_t)(info.height-1)*rowStride+rowBytes>source.length)return ImageWriteResult(ImageWriteError.truncatedInput);
    const across=(info.width+info.tileWidth-1)/info.tileWidth, down=(info.height+info.tileLength-1)/info.tileLength;
    const tiles=cast(size_t)across*down, rawBytes=cast(size_t)info.tileWidth*info.tileLength*pixelBytes;
    auto compressed=new ubyte[][](tiles); size_t compressedBytes;
    foreach(size_t n;0..tiles){auto raw=new ubyte[](rawBytes);const ty=n/across,tx=n%across;
        foreach(size_t y;0..info.tileLength){const sy=ty*info.tileLength+y;if(sy>=info.height)break;const sx=tx*info.tileWidth;const cp=sx+info.tileWidth>info.width?info.width-sx:info.tileWidth;
            raw[y*info.tileWidth*pixelBytes..y*info.tileWidth*pixelBytes+cp*pixelBytes]=source[sy*rowStride+sx*pixelBytes..sy*rowStride+(sx+cp)*pixelBytes];}
        auto encoded=new ubyte[](rawBytes*2+64*1024);auto result=encodeJpeg(Info(info.tileWidth,info.tileLength,info.channels),raw[],info.tileWidth*pixelBytes,encoded[],EncodeOptions(75,Sampling.s444));
        if(result.status!=Status.ok)return ImageWriteResult(result.status==Status.destinationTooSmall?ImageWriteError.outputLimitExceeded:ImageWriteError.sourceFailure);
        compressed[n]=encoded[0..result.written].dup;if(compressedBytes>size_t.max-result.written)return ImageWriteResult(ImageWriteError.outputLimitExceeded);compressedBytes+=result.written;}
    const entries=11U,ifdEnd=16+8+entries*20+8,offsets=ifdEnd,counts=offsets+tiles*8,pixels=counts+tiles*8;
    if(pixels>options.maximumOutputBytes||compressedBytes>size_t.max-pixels||pixels+compressedBytes>options.maximumOutputBytes)return ImageWriteResult(ImageWriteError.outputLimitExceeded);
    auto buf=new ubyte[](pixels+compressedBytes);buf[0]='I';buf[1]='I';p16(buf,2,43);p16(buf,4,8);p16(buf,6,0);p64(buf,8,16);p64(buf,16,entries);size_t p=24;
    ulong bitsValue; foreach(size_t i;0..info.channels) bitsValue|=cast(ulong)8<<(i*16);
    e(buf,p,256,16,1,info.width);e(buf,p,257,16,1,info.height);e(buf,p,258,3,info.channels,bitsValue);e(buf,p,259,3,1,7);e(buf,p,262,3,1,info.channels==1?1:2);e(buf,p,277,3,1,info.channels);e(buf,p,284,3,1,1);e(buf,p,322,16,1,info.tileWidth);e(buf,p,323,16,1,info.tileLength);e(buf,p,324,16,tiles,offsets);e(buf,p,325,16,tiles,counts);p64(buf,p,0);
    size_t data=pixels;foreach(size_t n;0..tiles){p64(buf,offsets+n*8,data);p64(buf,counts+n*8,compressed[n].length);buf[data..data+compressed[n].length]=compressed[n][];data+=compressed[n].length;}
    auto w=sink.write(buf[]);if(w.hasError)return mapSinkFailure(w.error().bytesWritten,w.error().kind);if(w.value().bytesWritten!=buf.length)return ImageWriteResult(ImageWriteError.sinkFailure,w.value().bytesWritten);return ImageWriteResult(ImageWriteError.none,buf.length,MetadataDisposition.notApplicable);
}

version (unittest)
{
    @safe unittest
    {
        import transport : ByteSink, WriteError, WriteFailure, WriteLimits, WriteResult;
        class Sink : ByteSink { size_t n; this(size_t n){this.n=n;}
            WriteResult write(scope const(ubyte)[] b, WriteLimits l=WriteLimits.init)
            { return WriteResult.failure(WriteFailure(WriteError.destinationFailure,n<b.length?n:b.length)); } }
        ubyte[3] pixel=[1,2,3];
        auto r=writeBigTiffJpegTiles(new Sink(7),TiffTileWriteInfo(1,1,1,1,3,1),pixel[],3);
        assert(r.error==ImageWriteError.sinkFailure && r.bytesWritten==7);
    }
}
