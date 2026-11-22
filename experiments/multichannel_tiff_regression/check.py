"""Independent GDAL fixtures: classic/BigTIFF, endian, inline/external SHORT arrays.

Usage: python3 check.py path/to/multichannel-tiff-regression
Only GDAL CLI and Python's standard library are required.
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile


def pixel(x, y):
    return [(x*17+y*11) % 256, (x*29+y*7) % 256, (x*3+y*31) % 256, 255]


with tempfile.TemporaryDirectory(prefix='imageio-component-bits-') as directory:
    root = Path(directory)
    source = root/'source.ppm'
    source.write_bytes(b'P6\n19 13\n255\n'+bytes(v for y in range(13) for x in range(19) for v in pixel(x, y)[:3]))
    expected = {}
    for big in [False, True]:
        for endian in ['LITTLE', 'BIG']:
            for channels in [2, 3, 4]:
                for depth in [8, 16]:
                    for tiled in [False, True]:
                        filename = root/f'{big}-{endian}-{channels}-{depth}-{tiled}.tif'
                        command = ['gdal_translate', '-q', '-of', 'GTiff', '-co', f'BIGTIFF={"YES" if big else "NO"}',
                                   '-co', f'ENDIANNESS={endian}', '-co', 'COMPRESS=NONE']
                        for c in range(channels):
                            command += ['-b', str(c+1) if c < 3 else 'mask']
                        if tiled:
                            command += ['-co', 'TILED=YES', '-co', 'BLOCKXSIZE=16', '-co', 'BLOCKYSIZE=16']
                        if depth == 16:
                            command += ['-ot', 'UInt16', '-scale', '0', '255', '0', '65535']
                        subprocess.check_call(command+[str(source), str(filename)])
                        header = filename.read_bytes()[:4]
                        assert header[:2] == (b'II' if endian == 'LITTLE' else b'MM')
                        assert int.from_bytes(header[2:], 'little' if endian == 'LITTLE' else 'big') == (43 if big else 42)
                        oracle = filename.with_suffix('.bin')
                        subprocess.check_call(['gdal_translate', '-q', '-of', 'ENVI', '-co', 'INTERLEAVE=BIP',
                                               str(filename), str(oracle)])
                        hdr = oracle.with_suffix('.hdr').read_text()
                        order = 'little' if re.search(r'byte order\s*=\s*0', hdr) else 'big'
                        assert re.search(r'header offset\s*=\s*0', hdr)
                        raw = oracle.read_bytes()
                        expected_pixels = [int.from_bytes(raw[i:i+depth//8], order)
                                           for i in range(0, len(raw), depth//8)]
                        assert len(expected_pixels) == 19*13*channels
                        # The source RGB map is known. Alpha/mask conversion by
                        # GDAL is read independently rather than guessed scaled.
                        for y in range(13):
                            for x in range(19):
                                for c in range(min(channels, 3)):
                                    assert expected_pixels[(y*19+x)*channels+c] == pixel(x, y)[c]*(257 if depth == 16 else 1)
                        expected[str(filename)] = (big, endian == 'LITTLE', channels, depth, expected_pixels)
    cases = json.loads(subprocess.check_output([str(Path(sys.argv[1]).resolve()), *expected], text=True))
    samples = 0
    for case in cases:
        big, little, channels, depth, full = expected[case['file']]
        assert (case['big_tiff'], case['little'], case['components'], case['bits']) == (big, little, channels, depth)
        x0, y0, width, height = case['region']
        values = [full[(y*19+x)*channels+c] for y in range(y0, y0+height)
                  for x in range(x0, x0+width) for c in range(channels)]
        raw = bytes(case['bytes'])
        actual = [int.from_bytes(raw[i:i+depth//8], 'little' if little else 'big') for i in range(0, len(raw), depth//8)]
        assert actual == values, (case['file'], case['region'])
        assert case['decoded_bytes'] == width*height*channels*(depth//8)
        assert case['encoded_bytes'] > 0
        samples += len(values)
    assert len(expected) == 48 and len(cases) == 192
    print(f'COMPONENT_BITS_GDAL=PASS; 48 classic/BigTIFF files, 192 full/ROI cases, {samples} exact samples')
