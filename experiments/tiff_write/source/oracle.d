module tiff_write_oracle;

import std.conv : to;
import std.file : read, write;
import tiff_write_research;

void main(string[] args)
{
    assert(args.length == 7);
    Info info = Info(to!uint(args[1]), to!uint(args[2]),
        to!ubyte(args[3]), to!ubyte(args[4]));
    auto input = cast(ubyte[])read(args[5]);
    auto req = requirements(info);
    assert(req.status == Status.ok);
    assert(requirements(Info(0, info.height, info.channels,
        info.sampleBytes)).status == Status.unsupported);
    assert(requirements(Info(info.width, info.height, 5,
        info.sampleBytes)).status == Status.unsupported);
    assert(requirements(Info(uint.max, uint.max, info.channels,
        info.sampleBytes)).status == Status.sizeLimit);
    auto output = new ubyte[req.fileBytes];
    output[] = 0xa5;
    assert(writeClassicTiff(info, input[], req.rowBytes, output[][0 .. $ - 1]).status ==
        Status.destinationTooSmall);
    foreach (b; output) assert(b == 0xa5);
    assert(writeClassicTiff(info, input[], req.rowBytes - 1, output[]).status ==
        Status.sourceTooSmall);
    foreach (b; output) assert(b == 0xa5);
    assert(writeClassicTiff(info, input[][0 .. $ - 1], req.rowBytes, output[]).status ==
        Status.sourceTooSmall);
    foreach (b; output) assert(b == 0xa5);
    auto written = writeClassicTiff(info, input[], req.rowBytes, output[]);
    assert(written.ok && written.written == req.fileBytes);
    write(args[6], output[0 .. written.written]);
}
