module bigtiff_sparse_probe;

import std.stdio : File;
import bigtiff_header;

void main(string[] args)
{
    assert(args.length == 2);
    enum long offset = 0x1_0000_0020L;
    ubyte[16] header = ['I', 'I', 43, 0, 8, 0, 0, 0,
        0x20, 0, 0, 0, 1, 0, 0, 0];
    ubyte[36] ifd;
    ifd[0] = 1; // one LONG8 entry
    ifd[8] = 0; ifd[9] = 1; // ImageWidth
    ifd[10] = 16; // LONG8
    ifd[12] = 1;
    ifd[20] = 77;
    {
        auto file = File(args[1], "wb+");
        file.rawWrite(header[]);
        file.seek(offset);
        file.rawWrite(ifd[]);
    }
    ubyte[16] readHeader;
    ubyte[36] readIfd;
    {
        auto file = File(args[1], "rb");
        file.rawRead(readHeader[]);
        file.seek(offset);
        file.rawRead(readIfd[]);
    }
    auto dir = parseDirectoryWindow(readHeader[], readIfd[], offset);
    assert(dir.status == Status.ok && dir.offset == offset && dir.count == 1);
    Entry entry;
    assert(entryAt(readIfd[], dir, 0, entry) == Status.ok);
    ulong width;
    assert(unsignedAt(readIfd[], dir, entry, 0, width) == Status.ok && width == 77);
    assert(parseDirectoryWindow(readHeader[], readIfd[][0 .. 35], offset).status == Status.truncated);
    assert(parseDirectoryWindow(readHeader[], readIfd[], offset - 1).status == Status.invalidOffset);
}
