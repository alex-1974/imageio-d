# Resource measurement

`resource_measure.sh` measures the optimized DMD/LDC benchmark binaries with
`/usr/bin/time`. The payload benchmarks also report copied bytes and a full
destination consume checksum.

The values are host-local evidence. They must not be treated as a portable
memory or throughput promise until repeated runs and additional platforms are
available.

`fixture_measure.sh` covers the complete selected uncompressed external
fixture matrix under DMD and LDC: gray8, RGB8 and gray16 single-strip,
planar RGB8 and tiled gray16. The oracles report destination/copy bytes and
zero full-image staging. `large_fixture_measure.sh` supplies repeated
1024×1024 planar/tiled measurements with active GDAL pixel comparisons.
