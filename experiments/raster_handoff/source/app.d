module app;

import core.stdc.stdlib : malloc;
import raster;
import std.stdio : writeln;

void main()
@system
{
    enum width = 7;
    enum height = 6;
    enum sampleBytes = ushort.sizeof;
    enum bytes = width * height * sampleBytes;
    void* memory = malloc(bytes);
    assert(memory !is null);
    auto samples = (cast(ushort*) memory)[0 .. width * height];
    foreach (y; 0 .. height)
        foreach (x; 0 .. width)
            samples[y * width + x] = cast(ushort)((x + 3) * 257 + (y + 2) * 4099);

    OwnedByteResource resource;
    assert(tryAdoptMallocResource(memory, bytes, resource));
    const PlaneByteLayout[1] layout = [PlaneByteLayout(0, width * sampleBytes, sampleBytes)];
    RasterLease!ubyte lease;
    assert(tryImportOwnedRaster!ubyte(resource, layout[], Region2D(0, 0, width, height), lease).ok);
    scope auto view = lease.view();
    ubyte value;
    assert(view.trySample(0, 3, 2 * sampleBytes, value));
    writeln("raster handoff: owned bytes=", bytes, " region=", width, "x", height,
        " lifetime=lease-bound");
}
