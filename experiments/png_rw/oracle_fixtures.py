#!/usr/bin/env python3
"""Independent Pillow/ImageMagick/zlib PNG fixtures and output oracle."""
import hashlib
import pathlib
import random
import struct
import subprocess
import sys
import zlib

from PIL import Image, PngImagePlugin


def chunk(name: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))


def png_bytes(width: int, height: int, bit_depth: int, color_type: int,
              compressed: bytes, split: bool = False) -> bytes:
    ihdr = struct.pack(">IIBBBBB", width, height, bit_depth, color_type, 0, 0, 0)
    pieces = [compressed]
    if split:
        pieces = [compressed[:1], compressed[1:5], compressed[5:-2], compressed[-2:]]
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
            b"".join(chunk(b"IDAT", part) for part in pieces) + chunk(b"IEND", b""))


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    aa, bb, cc = abs(p - a), abs(p - b), abs(p - c)
    return a if aa <= bb and aa <= cc else b if bb <= cc else c


def filter_rows(raw: bytes, width: int, height: int, bpp: int, kind: int) -> bytes:
    row_size = width * bpp
    out = bytearray()
    for y in range(height):
        out.append(kind)
        row = raw[y * row_size:(y + 1) * row_size]
        above = raw[(y - 1) * row_size:y * row_size] if y else bytes(row_size)
        for x, value in enumerate(row):
            a = row[x - bpp] if x >= bpp else 0
            b = above[x]
            c = above[x - bpp] if x >= bpp else 0
            predictor = (0, a, b, (a + b) // 2, paeth(a, b, c))[kind]
            out.append((value - predictor) & 255)
    return bytes(out)


def fixture(root: pathlib.Path, name: str, png: bytes, raw: bytes) -> None:
    (root / (name + ".png")).write_bytes(png)
    (root / (name + ".raw")).write_bytes(raw)
    print(name, "png", hashlib.sha256(png).hexdigest(), "raw", hashlib.sha256(raw).hexdigest())


def raw_pattern(width: int, height: int, channels: int, depth: int) -> bytes:
    maximum = 255 if depth == 8 else 65535
    values = bytearray()
    for y in range(height):
        for x in range(width):
            for c in range(channels):
                value = (x * 1423 + y * 2707 + c * 3971 + x * y * 17) & maximum
                values.extend(value.to_bytes(depth // 8, "big"))
    return bytes(values)


def packed_rows(values: list[int], width: int, height: int, depth: int) -> bytes:
    result = bytearray()
    for y in range(height):
        for x in range(0, width, 8 // depth):
            byte = 0
            for offset in range(8 // depth):
                if x + offset < width:
                    byte |= values[y * width + x + offset] << (8 - depth * (offset + 1))
            result.append(byte)
    return bytes(result)


def read_only_fixture(root: pathlib.Path, name: str, png: bytes,
                      native: bytes, expected_pixels: bytes) -> None:
    (root / (name + ".png")).write_bytes(png)
    (root / (name + ".native")).write_bytes(native)
    with Image.open(root / (name + ".png")) as image:
        # The independent decoder must reconstruct visible pixel values.
        if image.convert("RGBA").tobytes() != expected_pixels:
            raise AssertionError(f"Pillow semantic mismatch: {name}")
    print(name, "png", hashlib.sha256(png).hexdigest(),
          "native", hashlib.sha256(native).hexdigest())


def imagemagick_encode(raw: bytes, width: int, height: int, channels: int, path: pathlib.Path) -> bytes:
    color_type = {2: "4", 3: "2", 4: "6"}[channels]
    mode = {2: "graya:-", 3: "rgb:-", 4: "rgba:-"}[channels]
    command = ["convert", "-size", f"{width}x{height}", "-depth", "16",
               "-endian", "MSB", mode, "-strip",
               "-define", "png:exclude-chunk=time,date",
               "-define", f"png:color-type={color_type}",
               str(path)]
    subprocess.run(command, input=raw, check=True)
    return path.read_bytes()


def prepare(root: pathlib.Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    width, height = 23, 17
    for name, mode, channels in [("gray8", "L", 1), ("graya8", "LA", 2),
                                 ("rgb8", "RGB", 3),
                                 ("rgba8", "RGBA", 4)]:
        raw = raw_pattern(width, height, channels, 8)
        image = Image.frombytes(mode, (width, height), raw)
        path = root / (name + ".png")
        if name == "rgb8":
            metadata = PngImagePlugin.PngInfo()
            metadata.add_text("research", "metadata-drop-must-be-explicit")
            image.save(path, pnginfo=metadata)
            plain = path.read_bytes()
            decorated = (plain[:33] + chunk(b"vpAg", b"before-idat") +
                         plain[33:-12] + chunk(b"vpAg", b"after-idat") + plain[-12:])
            path.write_bytes(decorated)
            (root / "metadata-unsafe.png").write_bytes(
                decorated[:33] + chunk(b"vpAU", b"depends-on-pixels") + decorated[33:])
            (root / "metadata-color.png").write_bytes(
                decorated[:33] + chunk(b"gAMA", struct.pack(">I", 45455)) + decorated[33:])
        else:
            image.save(path)
        fixture(root, name, path.read_bytes(), raw)
    wide = raw_pattern(128, 128, 3, 8)
    wide_path = root / "rgb8-128.png"
    Image.frombytes("RGB", (128, 128), wide).save(wide_path)
    fixture(root, "rgb8-128", wide_path.read_bytes(), wide)
    noise = random.Random(1337).randbytes(width * height * 3)
    noise_path = root / "rgb8-noise.png"
    Image.frombytes("RGB", (width, height), noise).save(noise_path)
    fixture(root, "rgb8-noise", noise_path.read_bytes(), noise)
    tiny_path = root / "gray8-tiny.png"
    Image.frombytes("L", (1, 1), b"\xff").save(tiny_path)
    fixture(root, "gray8-tiny", tiny_path.read_bytes(), b"\xff")
    rgb_native = raw_pattern(width, height, 3, 8)
    first = rgb_native[:3]
    transparent_key = bytes(component for value in first for component in (0, value))
    rgb_ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    rgb_filtered = filter_rows(rgb_native, width, height, 3, 0)
    rgb_trns = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", rgb_ihdr) +
                chunk(b"tRNS", transparent_key) +
                chunk(b"IDAT", zlib.compress(rgb_filtered)) + chunk(b"IEND", b""))
    fixture(root, "rgb8-trns", rgb_trns, rgb_native)
    raw16 = raw_pattern(width, height, 1, 16)
    gray16 = Image.frombytes("I;16", (width, height),
                             b"".join(raw16[i:i + 2][::-1] for i in range(0, len(raw16), 2)))
    gray16.save(root / "gray16.png")
    fixture(root, "gray16", (root / "gray16.png").read_bytes(), raw16)
    for name, channels in [("graya16", 2), ("rgb16", 3), ("rgba16", 4)]:
        raw = raw_pattern(width, height, channels, 16)
        path = root / (name + ".png")
        fixture(root, name, imagemagick_encode(raw, width, height, channels, path), raw)
    tiny = raw_pattern(9, 5, 1, 8)
    for kind in range(5):
        payload = zlib.compress(filter_rows(tiny, 9, 5, 1, kind))
        fixture(root, f"filter{kind}", png_bytes(9, 5, 8, 0, payload, split=True), tiny)
    bad = zlib.compress(bytes([5]) + tiny[:9] + filter_rows(tiny, 9, 5, 1, 0)[10:])
    (root / "bad-filter.png").write_bytes(png_bytes(9, 5, 8, 0, bad))
    indexed = Image.frombytes("P", (9, 5), tiny)
    indexed.save(root / "indexed.png")
    regular = (root / "filter0.png").read_bytes()
    (root / "bad-crc.png").write_bytes(regular[:-1] + bytes([regular[-1] ^ 1]))
    # An ancillary chunk between IDAT chunks makes a later IDAT illegal.
    compressed = zlib.compress(filter_rows(tiny, 9, 5, 1, 0))
    ihdr = struct.pack(">IIBBBBB", 9, 5, 8, 0, 0, 0, 0)
    (root / "bad-order.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
        chunk(b"IDAT", compressed[:5]) + chunk(b"tEXt", b"k\0v") +
        chunk(b"IDAT", compressed[5:]) + chunk(b"IEND", b""))
    (root / "unknown-critical.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
        chunk(b"ABCD", b"x") + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
    (root / "apng-marker.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
        chunk(b"acTL", struct.pack(">II", 2, 0)) +
        chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
    (root / "trns.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
        chunk(b"tRNS", b"\x00\x00") + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
    for depth in (1, 2, 4):
        maximum = (1 << depth) - 1
        indices = [(x + 2 * y) % (maximum + 1) for y in range(5) for x in range(9)]
        native = packed_rows(indices, 9, 5, depth)
        scanlines = filter_rows(native, (9 * depth + 7) // 8, 5, 1, 4)
        gray = png_bytes(9, 5, depth, 0, zlib.compress(scanlines), split=True)
        visible = bytearray()
        for value in indices:
            sample = round(value * 255 / maximum)
            visible.extend((sample, sample, sample, 255))
        read_only_fixture(root, f"gray{depth}", gray, native, bytes(visible))
    for depth in (1, 2, 4, 8):
        entries = 1 << depth
        indices = [(x + 2 * y) % entries for y in range(5) for x in range(9)]
        native = packed_rows(indices, 9, 5, depth)
        scanlines = filter_rows(native, (9 * depth + 7) // 8, 5, 1, 3)
        ihdr = struct.pack(">IIBBBBB", 9, 5, depth, 3, 0, 0, 0)
        palette = bytes(component for i in range(entries)
                        for component in (i * 17 % 256, 0, 255 - i * 7 % 256))
        alpha = bytes((255 - i * 13) % 256 for i in range(entries))
        compressed = zlib.compress(scanlines)
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
               chunk(b"PLTE", palette) + chunk(b"tRNS", alpha) +
               chunk(b"IDAT", compressed[:2]) + chunk(b"IDAT", compressed[2:]) +
               chunk(b"IEND", b""))
        visible = bytes(component for i in indices for component in
                        (palette[3 * i], palette[3 * i + 1],
                         palette[3 * i + 2], alpha[i]))
        read_only_fixture(root, f"indexed{depth}", png, native, visible)
    small_ihdr = struct.pack(">IIBBBBB", 2, 1, 1, 3, 0, 0, 0)
    small_zlib = zlib.compress(b"\x00\x40")  # indices 0, 1
    (root / "indexed-missing-plte.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", small_ihdr) +
        chunk(b"IDAT", small_zlib) + chunk(b"IEND", b""))
    (root / "indexed-out-of-range.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", small_ihdr) +
        chunk(b"PLTE", b"\x00\x00\x00") +
        chunk(b"IDAT", small_zlib) + chunk(b"IEND", b""))
    (root / "indexed-bad-trns.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", small_ihdr) +
        chunk(b"PLTE", b"\x00\x00\x00") + chunk(b"tRNS", b"\x00\xff") +
        chunk(b"IDAT", small_zlib) + chunk(b"IEND", b""))
    altered = bytearray(zlib.compress(filter_rows(tiny, 9, 5, 1, 0)))
    altered[-1] ^= 1  # zlib Adler-32 fails, PNG chunk CRC remains valid.
    (root / "bad-adler.png").write_bytes(png_bytes(9, 5, 8, 0, bytes(altered)))


def verify(path: pathlib.Path, raw: bytes, name: str) -> None:
    if name in ("graya16", "rgb16", "rgba16"):
        mode = {"graya16": "graya:-", "rgb16": "rgb:-", "rgba16": "rgba:-"}[name]
        decoded = subprocess.run(["convert", str(path), "-depth", "16", "-endian", "MSB", mode],
                                 check=True, capture_output=True).stdout
    elif name == "gray16":
        with Image.open(path) as image:
            decoded = b"".join(int(value).to_bytes(2, "big")
                               for value in image.get_flattened_data())
    else:
        with Image.open(path) as image:
            decoded = image.tobytes()
    if decoded != raw:
        raise AssertionError(f"independent output decoder mismatch: {name} {path}")


def chunks(path: pathlib.Path) -> list[tuple[bytes, bytes]]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    result = []
    pos = 8
    while pos < len(data):
        length = struct.unpack_from(">I", data, pos)[0]
        name = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        crc = struct.unpack_from(">I", data, pos + 8 + length)[0]
        assert zlib.crc32(name + payload) == crc
        result.append((name, payload))
        pos += length + 12
    assert pos == len(data) and result[-1][0] == b"IEND"
    return result


if __name__ == "__main__":
    operation, folder = sys.argv[1], pathlib.Path(sys.argv[2])
    if operation == "prepare":
        prepare(folder)
    elif operation == "verify":
        compiler = sys.argv[3]
        for expected in sorted(folder.glob("*.raw")):
            name = expected.stem
            verify(folder / (name + ".png"), expected.read_bytes(), name)
            verify(folder / (name + f"-{compiler}.png"), expected.read_bytes(), name)
            verify(folder / (name + f"-{compiler}-adaptive.png"), expected.read_bytes(), name)
            verify(folder / (name + f"-{compiler}-fast.png"), expected.read_bytes(), name)
            verify(folder / (name + f"-{compiler}-stored.png"), expected.read_bytes(), name)
            verify(folder / (name + f"-{compiler}-row-stream.png"), expected.read_bytes(), name)
        for expected in sorted(folder.glob("*.native")):
            with Image.open(folder / (expected.stem + ".png")) as image:
                image.load()
        safe_original = chunks(folder / "rgb8.png")
        safe_output = chunks(folder / f"rgb8-{compiler}-metadata.png")
        safe_names = [name for name, _ in safe_output]
        assert [entry for entry in safe_output if entry[0] not in (b"IHDR", b"IDAT", b"IEND")] == [
            entry for entry in safe_original if entry[0] not in (b"IHDR", b"IDAT", b"IEND")]
        assert safe_names.index(b"vpAg") < safe_names.index(b"IDAT")
        assert safe_names[-2] == b"vpAg"
        verify(folder / f"rgb8-{compiler}-metadata.png", (folder / "rgb8.raw").read_bytes(), "rgb8")
        assert b"vpAU" not in [name for name, _ in chunks(folder / "metadata-unsafe-dropped.png")]
        assert (b"gAMA", struct.pack(">I", 45455)) in chunks(folder / "metadata-color-kept.png")
        for name in ("metadata-unsafe-dropped", "metadata-color-kept"):
            verify(folder / (name + ".png"), (folder / "rgb8.raw").read_bytes(), "rgb8")
        print(f"independent PNG input/output oracle passed: {compiler}")
    else:
        raise SystemExit("expected prepare or verify")
