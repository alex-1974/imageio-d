"""Independent reopen of the technical JPEG read/modify/write probe."""

import subprocess
import sys
from pathlib import Path

from PIL import Image


def main() -> None:
    path = Path(sys.argv[1])
    expected_exif = Path(sys.argv[2]).read_bytes()
    expected_icc = Path(sys.argv[3]).read_bytes()
    with Image.open(path) as image:
        image.load()
        assert image.mode == "RGB" and image.size == (19, 11)
        assert image.info.get("exif") == expected_exif
        assert image.info.get("icc_profile") == expected_icc
    with Image.open(str(path) + ".drop.jpg") as image:
        image.load()
        assert image.mode == "RGB" and image.size == (19, 11)
        assert "exif" not in image.info and "icc_profile" not in image.info
    for item in (path, Path(str(path) + ".drop.jpg")):
        subprocess.run(["magick", "identify", str(item)],
                       check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
