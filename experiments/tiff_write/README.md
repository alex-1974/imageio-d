# Classic TIFF write research slice

Run `sh check.sh` for an independent GDAL pixel and header oracle under DMD
and LDC. This is not a public package or a complete TIFF writer.
Local matrix: DMD 2.111.0, LDC 1.42.0, GDAL 3.13.3. The 19×11 RGBA16
fixture produced identical TIFF bytes under both compilers (SHA-256
`6445ee94d60a18c65a9f823df6164ccaccbcc916856767ac9953396991bc894a`);
raw pixel SHA-256 is
`e9097c375ef6b3b6b261b9c9af76ed9e48a5f822987dc66d9edd74660a09973a`.

The Pure-D probe writes one uncompressed, chunky, little-endian strip for
unsigned 8-/16-bit gray, gray+alpha, RGB and RGBA. The caller owns source and
output. It performs no colour, gamma, CRS or NoData interpretation. Alpha is
unassociated. No metadata transfer, compression, tiling, BigTIFF, planar
storage or multi-strip output is implemented. The preflight failure cases
leave output untouched; persistent sink/partial-write behavior is not yet
established.
