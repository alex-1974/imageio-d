#!/usr/bin/env python3
"""Independent Pillow/ImageMagick oracle for Pure-D JPEG output."""
import pathlib
import subprocess
import sys
import math
from PIL import Image

root = pathlib.Path(sys.argv[1])
compiler = sys.argv[2]
for name, mode in (("baseline-gray", "L"), ("baseline-rgb", "RGB")):
    measurements = []
    for quality in (1, 30, 75, 95, 100):
        path = root / f"{name}-{compiler}-q{quality}.jpg"
        with Image.open(path) as image:
            image.load()
            assert image.format == "JPEG" and image.size == (19, 11) and image.mode == mode
            assert sorted(image.quantization) == ([0] if mode == "L" else [0, 1])
            expected_dc = {1: (255, 255), 30: (27, 28), 75: (8, 9),
                           95: (2, 2), 100: (1, 1)}[quality]
            assert image.quantization[0][0] == expected_dc[0]
            if mode == "RGB":
                assert image.quantization[1][0] == expected_dc[1]
            pillow = image.tobytes()
        magick = subprocess.run(
            ["magick", str(path), "-depth", "8", "gray:-" if mode == "L" else "rgb:-"],
            check=True, capture_output=True).stdout
        assert pillow == magick, "independent decoders disagree on research output"
        original = (root / f"{name}.raw").read_bytes()
        errors = [abs(a - b) for a, b in zip(pillow, original)]
        maximum = max(errors)
        mean = sum(errors) / len(errors)
        p95 = sorted(errors)[int(0.95 * (len(errors) - 1))]
        mse = sum(error * error for error in errors) / len(errors)
        psnr = math.inf if mse == 0 else 10 * math.log10(255 * 255 / mse)
        measurements.append((path.stat().st_size, mean))
        print(name, compiler, "quality", quality, "bytes", path.stat().st_size,
              "max_error", maximum, "mean_error", mean,
              "p95_error", p95, "psnr_db", psnr)
        if quality >= 95:
            assert maximum <= 15 and mean <= 4
    assert measurements[0][0] < measurements[1][0] < measurements[2][0]
    assert measurements[0][1] > measurements[1][1] > measurements[2][1]
for sampling, factors in (("422", (2, 1)), ("420", (2, 2))):
    path = root / f"baseline-rgb-{compiler}-{sampling}.jpg"
    with Image.open(path) as image:
        image.load()
        assert image.size == (19, 11) and image.mode == "RGB"
        assert image.layer[0][1:3] == factors
        assert all(layer[1:3] == (1, 1) for layer in image.layer[1:])
        pillow = image.tobytes()
    magick = subprocess.run(
        ["magick", str(path), "-depth", "8", "rgb:-"],
        check=True, capture_output=True).stdout
    assert pillow == magick, "independent subsampled decoders disagree"
    original = (root / "baseline-rgb.raw").read_bytes()
    errors = [abs(a - b) for a, b in zip(pillow, original)]
    print("baseline-rgb", compiler, sampling, "bytes", path.stat().st_size,
          "max_error", max(errors), "mean_error", sum(errors) / len(errors))
    assert max(errors) <= 150 and sum(errors) / len(errors) <= 25
for name, mode, restarts in (("baseline-gray", "L", 5),
                             ("baseline-rgb", "RGB", 5),
                             ("baseline-rgb-422", "RGB", 3),
                             ("baseline-rgb-420", "RGB", 1)):
    path = root / f"{name}-{compiler}-rst1.jpg"
    encoded = path.read_bytes()
    assert b"\xff\xdd\x00\x04\x00\x01" in encoded
    for i in range(restarts):
        assert encoded.count(bytes((0xff, 0xd0 + i))) == 1
    with Image.open(path) as image:
        image.load()
        assert image.size == (19, 11) and image.mode == mode
        pillow = image.tobytes()
    magick = subprocess.run(
        ["magick", str(path), "-depth", "8", "gray:-" if mode == "L" else "rgb:-"],
        check=True, capture_output=True).stdout
    assert pillow == magick
    reference = root / (f"{name}-{compiler}-q95.jpg" if name in
                        ("baseline-gray", "baseline-rgb") else
                        f"baseline-rgb-{compiler}-{name[-3:]}.jpg")
    with Image.open(reference) as image:
        image.load()
        assert pillow == image.tobytes()
    print(name, compiler, "restart_interval", 1, "bytes", len(encoded))
bad = bytearray((root / f"baseline-rgb-{compiler}-rst1.jpg").read_bytes())
first = bad.index(b"\xff\xd0")
bad[first + 1] = 0xd1
(root / f"bad-restart-{compiler}.jpg").write_bytes(bad)
exif = (root / "metadata.exif").read_bytes()
icc = (root / "metadata.icc").read_bytes()
with Image.open(root / f"baseline-rgb-{compiler}-metadata.jpg") as image:
    image.load()
    assert image.info.get("exif") == exif
    assert image.info.get("icc_profile") == icc
    assert image.getexif().get(274) == 6
    copied_pixels = image.tobytes()
with Image.open(root / f"baseline-rgb-{compiler}-metadata.jpg.drop.jpg") as image:
    image.load()
    assert "exif" not in image.info and "icc_profile" not in image.info
    assert image.tobytes() == copied_pixels
with Image.open(root / f"baseline-rgb-{compiler}-q95.jpg") as image:
    image.load()
    assert image.tobytes() == copied_pixels
print("metadata", compiler, "EXIF/ICC copied or explicitly discarded")
with Image.open(root / f"baseline-rgb-{compiler}-metadata-large.jpg") as image:
    image.load()
    assert image.info.get("exif") == exif
    assert image.info.get("icc_profile") == (root / "metadata-large.icc").read_bytes()
    assert image.tobytes() == copied_pixels
print("metadata", compiler, "multi-segment ICC profile reassembled")
bad_icc = bytearray((root / f"baseline-rgb-{compiler}-metadata-large.jpg").read_bytes())
first = bad_icc.index(b"ICC_PROFILE\x00")
second = bad_icc.index(b"ICC_PROFILE\x00", first + 1)
bad_icc[second + 12] = 1  # duplicate sequence number; part 2 is missing
(root / f"bad-icc-sequence-{compiler}.jpg").write_bytes(bad_icc)
