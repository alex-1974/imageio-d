#!/usr/bin/env python3
"""Larger deterministic JPEG research corpus with two independent decoders."""
import pathlib
import subprocess
import sys
import math

from PIL import Image


CASES = (
    ("gray-single", 1, 1, "L", 100, "444", 0),
    ("rgb-thin", 1, 19, "RGB", 95, "420", 1),
    ("rgb-edge", 17, 19, "RGB", 95, "420", 1),
    ("rgb-edge-422", 17, 19, "RGB", 95, "422", 1),
    ("rgb-gradient", 257, 193, "RGB", 85, "420", 7),
    ("rgb-texture", 256, 256, "RGB", 95, "444", 13),
)


def pixels(name, width, height, mode):
    if mode == "L":
        return bytes([127]) * (width * height)
    result = bytearray()
    for y in range(height):
        for x in range(width):
            if name.startswith("rgb-edge"):
                result.extend((255 if (x // 3 + y // 5) % 2 else 0,
                               (x * 11 + y * 7) & 255,
                               0 if (x // 3 + y // 5) % 2 else 255))
            elif name == "rgb-gradient":
                result.extend(((x + y) & 255, (2 * x + y) & 255,
                               (x + 3 * y) & 255))
            else:
                result.extend(((x * 73 ^ y * 151 ^ x * y * 17) & 255,
                               (x * 19 ^ y * 41 ^ x * y * 29) & 255,
                               (x * 97 ^ y * 7 ^ x * y * 13) & 255))
    return bytes(result)


root = pathlib.Path(sys.argv[2])
if sys.argv[1] == "generate":
    root.mkdir(parents=True, exist_ok=True)
    for name, width, height, mode, *_ in CASES:
        (root / f"{name}.raw").write_bytes(pixels(name, width, height, mode))
elif sys.argv[1] == "verify":
    compiler = sys.argv[3]
    for name, width, height, mode, quality, sampling, restart in CASES:
        print("verifying", name, compiler, flush=True)
        path = root / f"{name}-{compiler}.jpg"
        with Image.open(path) as image:
            image.load()
            assert image.size == (width, height) and image.mode == mode
            if mode == "RGB":
                assert image.layer[0][1:3] == {
                    "444": (1, 1), "422": (2, 1), "420": (2, 2)}[sampling]
            pillow = image.tobytes()
        magick = subprocess.run(
            ["magick", str(path), "-depth", "8",
             "gray:-" if mode == "L" else "rgb:-"],
            check=True, capture_output=True).stdout
        assert len(pillow) == len(magick) == width * height * len(mode)
        decoder_errors = [abs(a - b) for a, b in zip(pillow, magick)]
        native = (root / f"{name}-{compiler}.jpg.decoded.raw").read_bytes()
        assert len(native) == len(pillow)
        native_errors = [abs(a - b) for a, b in zip(native, pillow)]
        # libjpeg-turbo switches to nearest-neighbour upsampling when a
        # subsampled component is at most two samples wide. Our deliberate
        # 3:1 interpolation still runs for the 1-pixel-wide image, so its
        # oracle tolerance is separate from the cross-MCU cases.
        tolerance = 30 if name == "rgb-thin" else 3
        assert max(native_errors) <= tolerance, (name, max(native_errors))
        original = (root / f"{name}.raw").read_bytes()
        errors = [abs(a - b) for a, b in zip(pillow, original)]
        assert sum(errors) / len(errors) < 80
        p95 = sorted(errors)[int(0.95 * (len(errors) - 1))]
        mse = sum(error * error for error in errors) / len(errors)
        psnr = math.inf if mse == 0 else 10 * math.log10(255 * 255 / mse)
        print(name, compiler, "pixels", width * height, "bytes", path.stat().st_size,
              "error_max", max(errors), "error_mean", sum(errors) / len(errors),
              "error_p95", p95, "psnr_db", psnr,
              "decoder_delta_max", max(decoder_errors),
              "native_delta_max", max(native_errors),
              "native_delta_mean", sum(native_errors) / len(native_errors))
else:
    raise SystemExit("expected generate or verify")
