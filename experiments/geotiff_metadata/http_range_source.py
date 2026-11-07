#!/usr/bin/env python3
"""Research-only HTTP Range source; not an imageio-d runtime dependency."""
from dataclasses import dataclass
from urllib.request import Request, urlopen


@dataclass
class Metrics:
    requests: int = 0
    bytes_requested: int = 0
    bytes_received: int = 0


class HttpRangeSource:
    def __init__(self, url: str, timeout: float = 30.0):
        self.url = url
        self.timeout = timeout
        self.metrics = Metrics()

    def read(self, offset: int, length: int) -> bytes:
        if offset < 0 or length <= 0:
            raise ValueError("range must be positive")
        end = offset + length - 1
        request = Request(self.url, headers={"Range": f"bytes={offset}-{end}"})
        with urlopen(request, timeout=self.timeout) as response:
            data = response.read()
            status = getattr(response, "status", 200)
            content_range = response.headers.get("Content-Range", "")
        self.metrics.requests += 1
        self.metrics.bytes_requested += length
        self.metrics.bytes_received += len(data)
        if status not in (200, 206):
            raise IOError(f"unexpected HTTP status {status}")
        if status == 206 and not content_range.startswith(f"bytes {offset}-"):
            raise IOError(f"unexpected Content-Range: {content_range}")
        if len(data) != length:
            raise IOError(f"short range: expected {length}, got {len(data)}")
        return data


def main() -> None:
    import sys
    url = sys.argv[1]
    source = HttpRangeSource(url)
    header = source.read(0, 16)
    assert header[:2] in (b"II", b"MM")
    source.read(1024, 1024)
    print("http ranges: requests=%d requested=%d received=%d" % (
        source.metrics.requests, source.metrics.bytes_requested,
        source.metrics.bytes_received))


if __name__ == "__main__":
    main()
