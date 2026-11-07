# External fixture oracle

`oracle_fixture.sh` creates an uncompressed grayscale TIFF with ImageMagick
and inspects it with GDAL. This provides an independently generated technical
fixture for the Pure-D parser work.

The generated file is under `.build/` and is not committed. The next gate is
to capture its byte hash and compare the Pure-D header/IFD result with the
GDAL-reported width, height, sample type, bit depth and compression.
