module http_app;

import transport;
import std.stdio : writefln;

void main(string[] args)
{
    assert(args.length > 1, "provide a COG URL");
    auto source = new CurlHttpSource(args[1]);
    ubyte[16] header;
    auto result = source.read(ByteRange(0, header.length), header[]);
    assert(result.ok && result.bytesRead == 16);
    assert(header[0] == 'I' && header[1] == 'I');
    writefln("HTTP transport to imageio consumer: range=%s signature=%s%s",
        result.bytesRead, cast(char)header[0], cast(char)header[1]);
}
