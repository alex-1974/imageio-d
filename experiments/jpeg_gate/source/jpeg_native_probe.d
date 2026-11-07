/// Research-only native component/colour-signalling regression.
module jpeg_native_probe;

import jpeg_research;
import std.file : write;
import std.conv : to;

void main(string[] args)
{
    assert(args.length == 2);
    foreach (sampling; [Sampling.s444, Sampling.s422, Sampling.s420])
    {
        const size_t width = 17, height = 19;
        const h = sampling == Sampling.s444 ? 1 : 2;
        const v = sampling == Sampling.s420 ? 2 : 1;
        ubyte[][3] source, decoded;
        ConstPlane[3] input;
        MutablePlane[3] output;
        size_t expectedSamples;
        foreach (size_t c; 0 .. 3)
        {
            const pw = (width + (c == 0 ? 1 : h) - 1) /
                (c == 0 ? 1 : h);
            const ph = (height + (c == 0 ? 1 : v) - 1) /
                (c == 0 ? 1 : v);
            const stride = pw + 5;
            source[c] = new ubyte[(ph - 1) * stride + pw + 11];
            decoded[c] = new ubyte[source[c].length];
            source[c][] = 0xa5;
            decoded[c][] = 0xa5;
            foreach (size_t y; 0 .. ph)
                foreach (size_t x; 0 .. pw)
                    source[c][y * stride + x] = cast(ubyte)(
                        (c * 37 + x * 7 + y * 5) & 255);
            input[c] = ConstPlane(source[c], stride);
            output[c] = MutablePlane(decoded[c], stride);
            expectedSamples += pw * ph;
        }
        auto encoded = new ubyte[1024 + 12 * 4 * 512 + 16];
        encoded[] = 0xa5;
        auto shortInput = input;
        shortInput[1].bytes = shortInput[1].bytes[0 .. 3];
        assert(encodeJfifPlanes(Info(width, height, 3), shortInput[],
            encoded[], EncodeOptions(100, sampling)).status == Status.truncated);
        foreach (b; encoded) assert(b == 0xa5);
        auto tooShort = encodeJfifPlanes(Info(width, height, 3), input[],
            encoded[0 .. 8], EncodeOptions(100, sampling));
        assert(tooShort.status == Status.destinationTooSmall);
        foreach (b; encoded) assert(b == 0xa5);
        auto saved = encodeJfifPlanes(Info(width, height, 3), input[],
            encoded[], EncodeOptions(100, sampling));
        assert(saved.ok && saved.written > 2);
        assert(encoded[saved.written - 2 .. saved.written] ==
            [cast(ubyte)0xff, 0xd9]);
        foreach (b; encoded[saved.written .. $]) assert(b == 0xa5);
        auto file = encoded[0 .. saved.written];
        auto frame = inspectJpegFrame(file);
        assert(frame.ok && frame.signal == ComponentSignal.jfifYCbCr);
        assert(frame.info.width == width && frame.info.height == height);
        assert(frame.horizontal[0] == h && frame.vertical[0] == v);
        auto read = decodeJpegPlanes(file, output[]);
        assert(read.ok && read.written == expectedSamples);
        foreach (size_t c; 0 .. 3)
        {
            const pw = (width + (c == 0 ? 1 : h) - 1) /
                (c == 0 ? 1 : h);
            const ph = (height + (c == 0 ? 1 : v) - 1) /
                (c == 0 ? 1 : v);
            const stride = input[c].rowStride;
            foreach (size_t y; 0 .. ph)
                foreach (size_t x; 0 .. pw)
                {
                    const a = cast(int)source[c][y * stride + x];
                    const b = cast(int)decoded[c][y * stride + x];
                    assert(a - b <= 3 && b - a <= 3);
                }
            foreach (size_t y; 0 .. ph - 1)
                foreach (b; decoded[c][y * stride + pw .. (y + 1) * stride])
                    assert(b == 0xa5);
            foreach (b; decoded[c][(ph - 1) * stride + pw .. $])
                assert(b == 0xa5);
        }
        auto shortOutput = output;
        shortOutput[2].bytes = shortOutput[2].bytes[0 .. 3];
        assert(decodeJpegPlanes(file, shortOutput[]).status ==
            Status.destinationTooSmall);
        auto unmarked = file[0 .. 2].dup ~ file[20 .. $].dup;
        assert(inspectJpegFrame(unmarked).signal == ComponentSignal.unknown);
        assert(decodeJpegPlanes(unmarked, output[]).ok);
        auto rgb = new ubyte[width * height * 3];
        assert(decodeJpeg(unmarked, rgb[], width * 3).status ==
            Status.unsupported);
        immutable ubyte[] adobe = [0xff, 0xee, 0x00, 0x0e,
            'A', 'd', 'o', 'b', 'e', 0x00, 0x64, 0, 0, 0, 0, 0];
        auto contradictory = file[0 .. 20].dup ~ adobe ~ file[20 .. $].dup;
        assert(inspectJpegFrame(contradictory).signal ==
            ComponentSignal.adobeRGB);
        assert(decodeJpegPlanes(contradictory, output[]).ok);
        assert(decodeJpeg(contradictory, rgb[], width * 3).status ==
            Status.unsupported);
        contradictory[20 + adobe.length - 1] = 2;
        assert(inspectJpegFrame(contradictory).signal ==
            ComponentSignal.unknown);
        assert(decodeJpeg(contradictory, rgb[], width * 3).status ==
            Status.unsupported);
        const suffix = sampling == Sampling.s444 ? "444" :
            sampling == Sampling.s422 ? "422" : "420";
        write(args[1] ~ "-" ~ suffix ~ ".jpg", file);
    }
    ubyte[13 * 7] gray;
    foreach (size_t i; 0 .. gray.length)
        gray[i] = cast(ubyte)((i * 3) & 255);
    ConstPlane[1] grayIn = [ConstPlane(gray[], 13)];
    ubyte[1024 + 2 * 512] grayFile;
    auto graySaved = encodeJfifPlanes(Info(13, 7, 1), grayIn[],
        grayFile[], EncodeOptions(100));
    assert(graySaved.ok);
    ubyte[13 * 7] grayOut;
    MutablePlane[1] grayPlanes = [MutablePlane(grayOut[], 13)];
    auto grayRead = decodeJpegPlanes(grayFile[0 .. graySaved.written],
        grayPlanes[]);
    assert(grayRead.ok && grayRead.written == gray.length);
    assert(inspectJpegFrame(grayFile[0 .. graySaved.written]).signal ==
        ComponentSignal.gray);
    foreach (size_t i; 0 .. gray.length)
    {
        const a = cast(int)gray[i], b = cast(int)grayOut[i];
        assert(a - b <= 3 && b - a <= 3);
    }
    write(args[1] ~ "-gray.jpg", grayFile[0 .. graySaved.written]);
}
