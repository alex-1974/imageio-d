#!/usr/bin/env python3
"""JPEG gate corpus/oracle setup only; deliberately no imageio JPEG codec."""
import hashlib
import json
import pathlib
import subprocess
import sys

from PIL import Image, ImageCms


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(folder: pathlib.Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    width, height = 19, 11
    gray = bytes((x * 17 + y * 23) % 256 for y in range(height) for x in range(width))
    rgb = bytes(component for y in range(height) for x in range(width)
                for component in ((x * 13 + y * 7) % 256,
                                  (x * 3 + y * 29) % 256,
                                  (x * 31 + y * 11) % 256))
    gray_image = Image.frombytes("L", (width, height), gray)
    rgb_image = Image.frombytes("RGB", (width, height), rgb)
    fixtures = [
        ("baseline-gray", gray_image, {"quality": 90, "progressive": False}),
        ("baseline-rgb", rgb_image, {"quality": 90, "progressive": False,
                                  "subsampling": 0}),
        ("baseline-rgb-422", rgb_image, {"quality": 90, "progressive": False,
                                      "subsampling": 1}),
        ("baseline-rgb-420", rgb_image, {"quality": 90, "progressive": False,
                                      "subsampling": 2}),
        ("progressive-rgb", rgb_image, {"quality": 90, "progressive": True,
                                     "subsampling": 0}),
        ("cmyk", rgb_image.convert("CMYK"), {"quality": 90}),
    ]
    exif = Image.Exif()
    exif[274] = 6
    profile_bytes = bytearray(
        ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    # LittleCMS stamps profile creation time; normalize its ICC header so
    # fixture hashes are reproducible across runs. Profile ID is already zero.
    profile_bytes[24:36] = bytes.fromhex("07e400010001000000000000")
    profile = bytes(profile_bytes)
    large_profile = bytearray(profile)
    large_profile.extend(b"\0" * (70_000 - len(large_profile)))
    large_profile[0:4] = len(large_profile).to_bytes(4, "big")
    (folder / "metadata-large.icc").write_bytes(large_profile)
    fixtures.append(("metadata-rgb", rgb_image,
                     {"quality": 90, "subsampling": 0, "exif": exif,
                      "icc_profile": profile}))
    manifest = {"generator": "Pillow", "pillow_version": Image.__version__,
                "width": width, "height": height, "fixtures": {}}
    for name, image, options in fixtures:
        path = folder / f"{name}.jpg"
        image.save(path, format="JPEG", **options)
        with Image.open(path) as decoded:
            decoded.load()
            mode = decoded.mode
            raw_pillow = decoded.tobytes()
            (folder / f"{name}.raw").write_bytes(raw_pillow)
            if name == "metadata-rgb":
                assert decoded.getexif().get(274) == 6
                assert decoded.info.get("icc_profile") == profile
                (folder / "metadata.exif").write_bytes(decoded.info["exif"])
                (folder / "metadata.icc").write_bytes(profile)
        raw_mode = {"L": "gray:-", "RGB": "rgb:-", "CMYK": "cmyk:-"}[mode]
        raw_magick = subprocess.run(
            ["magick", str(path), "-depth", "8", raw_mode],
            check=True, capture_output=True).stdout
        if len(raw_magick) != len(raw_pillow):
            raise AssertionError(f"decoder output length differs: {name}")
        errors = [abs(a - b) for a, b in zip(raw_pillow, raw_magick)]
        manifest["fixtures"][name] = {
            "sha256": digest(path.read_bytes()), "bytes": path.stat().st_size,
            "mode": mode, "pillow_raw_sha256": digest(raw_pillow),
            "magick_raw_sha256": digest(raw_magick),
            "decoder_max_difference": max(errors, default=0),
            "decoder_mean_difference": sum(errors) / len(errors) if errors else 0,
            "progressive": bool(options.get("progressive", False)),
        }
    truncated = (folder / "baseline-rgb.jpg").read_bytes()[:-32]
    (folder / "truncated.jpg").write_bytes(truncated)
    baseline = (folder / "baseline-rgb.jpg").read_bytes()
    dqt = baseline.find(b"\xff\xdb")
    assert dqt > 0
    bad_quant = bytearray(baseline)
    bad_quant[dqt + 5] = 0  # first quantizer coefficient must be nonzero
    (folder / "bad-quant.jpg").write_bytes(bad_quant)
    dht = baseline.find(b"\xff\xc4")
    assert dht > 0
    bad_huff = bytearray(baseline)
    bad_huff[dht + 5] = 255  # impossible code count at length 1
    (folder / "bad-huff.jpg").write_bytes(bad_huff)
    sof = baseline.find(b"\xff\xc0")
    assert sof > 0 and baseline[sof + 11] == 0x11
    unsupported_440 = bytearray(baseline)
    unsupported_440[sof + 11] = 0x12  # vertical-only luma sampling is not admitted
    (folder / "unsupported-440.jpg").write_bytes(unsupported_440)
    app14 = b"\xff\xee\x00\x0eAdobe\x00\x64\x00\x00\x00\x00\x00"
    (folder / "adobe-rgb.jpg").write_bytes(baseline[:2] + app14 + baseline[2:])
    try:
        with Image.open(folder / "truncated.jpg") as broken:
            broken.load()
    except OSError:
        pass
    else:
        raise AssertionError("negative fixture did not fail Pillow decode")
    manifest["negative"] = {"truncated_sha256": digest(truncated)}
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    run(pathlib.Path(sys.argv[1]))
