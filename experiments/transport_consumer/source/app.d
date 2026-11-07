module app;

import transport;
import std.stdio : writefln;

void main(string[] args)
{
    assert(args.length > 1, "provide a TIFF fixture");
    auto source = new FileSource(args[1]);
    ubyte[8] header;
    auto headerResult = source.read(ByteRange(0, header.length), header[]);
    assert(headerResult.ok && header[0] == 'I' && header[1] == 'I');

    ubyte[65] payload;
    auto payloadResult = source.read(ByteRange(881, payload.length), payload[]);
    assert(payloadResult.ok && payloadResult.bytesRead == payload.length);

    auto rejected = source.read(ByteRange(881, 65), payload[], ReadLimits(32));
    assert(rejected.error == ReadError.limitExceeded);
    writefln("transport consumer: header=%s payload=%s limited=%s",
        headerResult.bytesRead, payloadResult.bytesRead, rejected.error);
}
