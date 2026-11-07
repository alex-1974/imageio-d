module bigtiff_oracle;

import std.file : read;
import std.conv : to;
import bigtiff_header;

void main(string[] args)
{
    assert(args.length == 4);
    auto bytes = cast(const(ubyte)[])read(args[1]);
    auto dir = parseDirectory(bytes);
    assert(dir.status == Status.ok);
    ulong width, height;
    foreach (i; 0 .. dir.count)
    {
        Entry e;
        assert(entryAt(bytes, dir, i, e) == Status.ok);
        if (e.tag != 256 && e.tag != 257) continue;
        ulong v;
        assert(unsignedAt(bytes, dir, e, 0, v) == Status.ok);
        if (e.tag == 256) width = v;
        else height = v;
    }
    assert(width == to!ulong(args[2]) && height == to!ulong(args[3]));
}
