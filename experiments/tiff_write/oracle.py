#!/usr/bin/env python3
"""Independent GDAL TIFF write oracle. No GDAL runtime in the D writer."""
import pathlib
import subprocess
import sys
import tempfile


def samples(width: int, height: int, channels: int, sample_bytes: int) -> bytes:
    mask = (1 << (8 * sample_bytes)) - 1
    return b"".join(((x * 139 + y * 773 + c * 3271) & mask).to_bytes(sample_bytes, "little")
                    for y in range(height) for x in range(width) for c in range(channels))


def verify(tiff: pathlib.Path, raw: pathlib.Path, width: int, height: int,
           channels: int, sample_bytes: int) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        result = pathlib.Path(temporary) / "decoded"
        data_type = "Byte" if sample_bytes == 1 else "UInt16"
        subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-ot", data_type,
                        "-co", "INTERLEAVE=BIP", str(tiff), str(result)], check=True)
        decoded = result.read_bytes()
        if decoded != raw.read_bytes():
            raise AssertionError(f"GDAL pixel mismatch: {tiff}")
        report = subprocess.run(["gdalinfo", str(tiff)], check=True,
                                capture_output=True, text=True).stdout
        if f"Size is {width}, {height}" not in report:
            raise AssertionError(f"GDAL dimensions mismatch: {tiff}")
        if report.count("Band ") != channels:
            raise AssertionError(f"GDAL band count mismatch: {tiff}")
        if sample_bytes == 2 and f"Type={data_type}" not in report:
            raise AssertionError(f"GDAL sample type mismatch: {tiff}")


if __name__ == "__main__":
    operation = sys.argv[1]
    if operation == "prepare":
        path = pathlib.Path(sys.argv[2])
        path.write_bytes(samples(*map(int, sys.argv[3:7])))
    elif operation == "verify":
        verify(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]),
               *map(int, sys.argv[4:8]))
    else:
        raise SystemExit("expected prepare or verify")
