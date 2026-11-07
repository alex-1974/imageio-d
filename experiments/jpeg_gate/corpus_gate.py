#!/usr/bin/env python3
"""Bounded real-content JPEG quality and malformed-input oracle; research only."""
import argparse
import datetime as dt
import io
import json
import pathlib
import tempfile

from PIL import Image, features

from benchmark_suite import (CASES, REAL_SOURCES, REPO, ROOT, command, compile_d,
                             digest, host_info, real_pixels, run_d, verify_case)


VARIANTS = ((30, "420"), (90, "420"), (100, "420"), (90, "444"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus-dir", type=pathlib.Path,
                        help="offline directory containing the three hash-pinned sources")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--mutations", type=int, default=64)
    args = parser.parse_args()
    if not 1 <= args.mutations <= 256:
        parser.error("--mutations must be in 1..256")
    report = {
        "schema": "imageio-d/jpeg-corpus-gate-v1",
        "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "git_head": command("git", "rev-parse", "HEAD", cwd=REPO),
        "git_dirty": bool(command("git", "status", "--porcelain", cwd=REPO)),
        "status": "diagnostic research, not format admission or security certification",
        "host": host_info(),
        "versions": {
            "dmd": command("dmd", "--version").splitlines()[0],
            "ldc2": command("ldc2", "--version").splitlines()[0],
            "pillow": Image.__version__,
            "libjpeg": features.version_codec("jpg"),
            "imagemagick": command("magick", "-version").splitlines()[0],
        },
        "source_sha256": {path.name: digest(path.read_bytes()) for path in
                          (ROOT / "source/jpeg_research.d",
                           ROOT / "source/jpeg_malformed_probe.d",
                           ROOT / "source/jpeg_benchmark.d",
                           ROOT / "benchmark_suite.py",
                           pathlib.Path(__file__))},
        "builds": {},
        "cases": {},
    }
    with tempfile.TemporaryDirectory(prefix="imageio-jpeg-corpus-") as temp:
        build = pathlib.Path(temp)
        binaries = {}
        for compiler in ("dmd", "ldc2"):
            binary, invocation = compile_d(compiler, build)
            binaries[compiler] = binary
            report["builds"][compiler] = {
                "invocation": invocation, "binary_sha256": digest(binary.read_bytes())}
        malformed = {}
        for compiler in binaries:
            binary = build / f"jpeg-malformed-{compiler}"
            flags = ["-O3" if compiler == "ldc2" else "-O", "-release",
                     "-boundscheck=on", "-dip1000"]
            command(compiler, *flags, f"-I={ROOT / 'source'}", f"-of={binary}",
                    str(ROOT / "source/jpeg_research.d"),
                    str(ROOT / "source/jpeg_malformed_probe.d"))
            malformed[compiler] = binary
            report["builds"][compiler]["malformed_binary_sha256"] = digest(
                binary.read_bytes())
        for source_name, source in REAL_SOURCES.items():
            width, height, mode, _, _ = CASES[source_name]
            raw = real_pixels(source_name, args.corpus_dir)
            source_report = {"source": source, "raw_sha256": digest(raw),
                             "variants": {}}
            report["cases"][source_name] = source_report
            image = Image.frombytes(mode, (width, height), raw)
            for quality, sampling in VARIANTS:
                name = f"{source_name}-q{quality}-{sampling}"
                (build / f"{name}.raw").write_bytes(raw)
                reference_output = io.BytesIO()
                image.save(reference_output, format="JPEG", quality=quality,
                           subsampling={"420": 2, "444": 0}[sampling],
                           progressive=False, optimize=False)
                reference = reference_output.getvalue()
                (build / f"{name}-reference.jpg").write_bytes(reference)
                case = (name, width, height, mode, quality, sampling)
                runs = {compiler: run_d(binary, case, build, True, 1)
                        for compiler, binary in binaries.items()}
                oracle = verify_case(case, build, runs)
                source_report["variants"][f"q{quality}-{sampling}"] = oracle
                if quality == 90 and sampling == "420":
                    source_report["malformed"] = {}
                    for compiler, binary in malformed.items():
                        source_report["malformed"][compiler] = command(
                            str(binary), str(build / f"{name}-reference.jpg"),
                            str(width), str(height), str(len(mode)),
                            str(args.mutations))
                print("validated", name, flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("record:", args.output)


if __name__ == "__main__":
    main()
