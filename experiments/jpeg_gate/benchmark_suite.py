#!/usr/bin/env python3
"""Reproducible, paired JPEG research benchmark; not an admission verdict."""
import argparse
import contextlib
import datetime as dt
import hashlib
import io
import json
import math
import os
import pathlib
import platform
import statistics
import subprocess
import tempfile
import time
import urllib.request

from PIL import Image, features


ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent.parent
CASES = {
    "gray-gradient": (512, 512, "L", 90, "444"),
    "rgb-smooth": (1024, 1024, "RGB", 90, "444"),
    "rgb-texture": (512, 512, "RGB", 90, "444"),
    "rgb-smooth-420": (1024, 1024, "RGB", 90, "420"),
    "real-flower-420": (480, 360, "RGB", 90, "420"),
    "real-landscape-420": (1600, 1200, "RGB", 90, "420"),
    "real-earth-420": (1280, 852, "RGB", 90, "420"),
}
REAL_SOURCES = {
    "real-flower-420": {
        "filename": "imageio-flower.jpg",
        "source_page": "https://github.com/python-pillow/Pillow/blob/cb77e1bfaa02449b2a61486ce02f509438c801a5/Tests/images/flower.jpg",
        "url": "https://raw.githubusercontent.com/python-pillow/Pillow/cb77e1bfaa02449b2a61486ce02f509438c801a5/Tests/images/flower.jpg",
        "sha256": "8a9d04b92d0de5836c59ede8ae421235488e4031e893e07b1fe7e4b78f6a9901",
        "license": "Pillow test fixture; image redistribution terms not independently verified",
    },
    "real-landscape-420": {
        "filename": "imageio-landscape.jpg",
        "source_page": "https://commons.wikimedia.org/wiki/File:Nature_Landscape_(248036051).jpeg",
        "url": "https://commons.wikimedia.org/wiki/Special:Redirect/file/Nature_Landscape_%28248036051%29.jpeg",
        "sha256": "300bfc83673a1e19c617134c7f4402bf70f01a51f8299d91083f32c516a19d7e",
        "license": "CC0; Semen Perez, Wikimedia Commons",
    },
    "real-earth-420": {
        "filename": "imageio-earth.jpg",
        "source_page": "https://commons.wikimedia.org/wiki/File:ISS047-E-1024_-_View_of_Earth.jpg",
        "url": "https://commons.wikimedia.org/wiki/Special:Redirect/file/ISS047-E-1024_-_View_of_Earth.jpg?width=1024",
        "sha256": "fefc7b5dfbc7dfbb8ddb3dde7fee3dc5fd58948fbc0639c4f6467ad0a6a73a4d",
        "license": "NASA public domain; Wikimedia Commons 1280x852 derivative",
    },
}


def command(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          capture_output=True).stdout.strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def cpu_frequency_khz():
    if not hasattr(os, "sched_getaffinity"):
        return None
    cpu = min(os.sched_getaffinity(0))
    path = pathlib.Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq")
    return int(path.read_text()) if path.exists() else None


def pixels(name, width, height, mode):
    raw = bytearray(width * height * len(mode))
    for y in range(height):
        for x in range(width):
            at = (y * width + x) * len(mode)
            if mode == "L":
                raw[at] = (x + y) & 255
            elif name == "rgb-texture":
                raw[at] = (x * 73 ^ y * 151 ^ x * y * 17) & 255
                raw[at + 1] = (x * 19 ^ y * 41 ^ x * y * 29) & 255
                raw[at + 2] = (x * 97 ^ y * 7 ^ x * y * 13) & 255
            else:
                raw[at] = (x + y) & 255
                raw[at + 1] = (2 * x + y) & 255
                raw[at + 2] = (x + 3 * y) & 255
    return bytes(raw)


def real_pixels(name, folder):
    source = REAL_SOURCES[name]
    if folder is None:
        with urllib.request.urlopen(source["url"], timeout=30) as response:
            encoded = response.read()
    else:
        encoded = (folder / source["filename"]).read_bytes()
    if digest(encoded) != source["sha256"]:
        raise RuntimeError(f"source hash changed: {name}")
    with Image.open(io.BytesIO(encoded)) as image:
        if image.size != CASES[name][:2] or image.mode != "RGB":
            raise RuntimeError(f"source shape/mode changed: {name}")
        return image.tobytes()


def differences(actual, expected, channels):
    assert len(actual) == len(expected)
    histogram = [0] * 256
    channel_sum = [0] * channels
    channel_max = [0] * channels
    squared = 0
    maximum = 0
    for index, (a, b) in enumerate(zip(actual, expected)):
        error = abs(a - b)
        histogram[error] += 1
        channel = index % channels
        channel_sum[channel] += error
        channel_max[channel] = max(channel_max[channel], error)
        maximum = max(maximum, error)
        squared += error * error
    count = len(actual)
    threshold = math.ceil(0.95 * count)
    cumulative = 0
    p95 = 0
    for error, frequency in enumerate(histogram):
        cumulative += frequency
        if cumulative >= threshold:
            p95 = error
            break
    mse = squared / count
    return {
        "max": maximum,
        "p95": p95,
        "mean": sum(channel_sum) / count,
        "psnr_db": None if mse == 0 else 10 * math.log10(255 * 255 / mse),
        "per_channel_mean": [total / (count // channels) for total in channel_sum],
        "per_channel_max": channel_max,
    }


def distribution(values):
    ordered = sorted(values)
    return {
        "samples_ms": [round(value / 1e6, 3) for value in values],
        "median_ms": round(statistics.median(values) / 1e6, 3),
        "min_ms": round(ordered[0] / 1e6, 3),
        "p10_ms": round(ordered[int(0.1 * (len(ordered) - 1))] / 1e6, 3),
        "p90_ms": round(ordered[int(0.9 * (len(ordered) - 1))] / 1e6, 3),
        "max_ms": round(ordered[-1] / 1e6, 3),
        "relative_spread": round((ordered[-1] - ordered[0]) /
                                 statistics.median(values), 3),
        "unstable_over_20pct_spread": (ordered[-1] - ordered[0]) /
            statistics.median(values) > 0.2,
    }


def compile_d(compiler, build, profile=False, legacy=False, float_color=False,
              sparse_idct=False):
    flags = ["-O", "-release", "-boundscheck=on", "-dip1000"]
    if compiler == "ldc2":
        flags[0] = "-O3"
    if profile:
        flags.append("-g")
    if legacy:
        flags.append(("-d-version=" if compiler == "ldc2" else "-version=") +
                     "JpegBitWriterLegacy")
    if float_color:
        flags.append(("-d-version=" if compiler == "ldc2" else "-version=") +
                     "JpegFloatColorTransform")
    if sparse_idct:
        flags.append(("-d-version=" if compiler == "ldc2" else "-version=") +
                     "JpegIdctSparse")
    binary = build / (f"jpeg-{'profile' if profile else 'benchmark'}-{compiler}"
                      f"{'-legacy' if legacy else ''}{'-float-color' if float_color else ''}"
                      f"{'-sparse-idct' if sparse_idct else ''}")
    invocation = [compiler, *flags, f"-I={ROOT / 'source'}",
                  f"-of={binary}", str(ROOT / "source/jpeg_research.d"),
                  str(ROOT / "source/jpeg_benchmark.d")]
    command(*invocation)
    return binary, invocation


def profile_d(case, build):
    binary, invocation = compile_d("ldc2", build, profile=True)
    name, width, height, mode, quality, sampling = case
    result = {"build": invocation, "binary_sha256": digest(binary.read_bytes())}
    for operation in ("encode", "decode"):
        data = build / f"perf-{operation}.data"
        run = ["perf", "record", "-q", "--no-inherit", "-F", "999", "-o", str(data),
               "--", str(binary), str(build / f"{name}.raw"),
               str(build / f"{name}-reference.jpg"), "-", "-", str(width),
               str(height), str(len(mode)), str(quality), sampling,
               operation, "12"]
        completed = subprocess.run(run, capture_output=True, text=True)
        if completed.returncode:
            result[operation] = {"error": completed.stderr.strip()}
            continue
        report = subprocess.run(
            ["perf", "report", "--stdio", "--no-children", "-g", "none",
             "--sort", "symbol",
             "--percent-limit", "1", "-i", str(data)],
            capture_output=True, text=True, check=True).stdout
        result[operation] = {"driver_output": completed.stdout.strip(),
                             "perf_report": report}
    return result


def compare_variant(case, build, candidate, rounds, repeats, variant):
    if variant == "idct":
        legacy = candidate
        candidate, invocation = compile_d("ldc2", build, sparse_idct=True)
        result = {"candidate_build": invocation,
                  "candidate_binary_sha256": digest(candidate.read_bytes()),
                  "legacy_binary_sha256": digest(legacy.read_bytes()),
                  "paired_rounds": []}
    else:
        legacy, invocation = compile_d("ldc2", build,
                                       legacy=variant == "bitwriter",
                                       float_color=variant == "color")
        result = {"legacy_build": invocation,
                  "legacy_binary_sha256": digest(legacy.read_bytes()),
                  "paired_rounds": []}
    for index in range(rounds):
        order = ("candidate", "legacy") if index % 2 == 0 else ("legacy", "candidate")
        samples = {}
        for backend in order:
            binary = candidate if backend == "candidate" else legacy
            samples[backend] = run_d(binary, case, build, index == 0, repeats)
        samples["pillow_control"] = run_pillow(
            Image.frombytes(case[3], (case[1], case[2]),
                            (build / f"{case[0]}.raw").read_bytes()),
            (build / f"{case[0]}-reference.jpg").read_bytes(),
            case[4], case[5], repeats)
        if variant != "idct" and samples["candidate"]["decode_checksum"] != samples["legacy"]["decode_checksum"]:
            raise RuntimeError("variant decode checksums differ")
        if variant == "bitwriter" and (
            samples["candidate"]["encoded_bytes"] != samples["legacy"]["encoded_bytes"] or
            index == 0 and samples["candidate"]["image_path"].read_bytes() !=
                samples["legacy"]["image_path"].read_bytes()
        ):
            raise RuntimeError("bitwriter variants produce different JPEG bytes")
        if variant == "idct" and index == 0:
            result["decoded_pixel_delta"] = differences(
                samples["candidate"]["decoded_path"].read_bytes(),
                samples["legacy"]["decoded_path"].read_bytes(), len(case[3]))
        result["paired_rounds"].append({backend: {
            "encode_ms": round(sample["encode_ns"] / 1e6, 3),
            "decode_ms": round(sample["decode_ns"] / 1e6, 3),
            "cpu_khz_before": sample["cpu_khz_before"],
            "cpu_khz_after": sample["cpu_khz_after"],
        } for backend, sample in samples.items()})
    for operation in ("encode", "decode"):
        result[f"candidate_{operation}"] = distribution(
            [row["candidate"][f"{operation}_ms"] * 1e6
             for row in result["paired_rounds"]])
        result[f"legacy_{operation}"] = distribution(
            [row["legacy"][f"{operation}_ms"] * 1e6
             for row in result["paired_rounds"]])
        result[f"paired_{operation}_candidate_over_legacy"] = [
            round(row["candidate"][f"{operation}_ms"] /
                  row["legacy"][f"{operation}_ms"], 3)
            for row in result["paired_rounds"]]
        result[f"pillow_control_{operation}"] = distribution(
            [row["pillow_control"][f"{operation}_ms"] * 1e6
             for row in result["paired_rounds"]])
        result[f"paired_{operation}_candidate_over_control"] = [
            round(row["candidate"][f"{operation}_ms"] /
                  row["pillow_control"][f"{operation}_ms"], 3)
            for row in result["paired_rounds"]]
    result["target_operation"] = "decode" if variant == "idct" else "encode"
    result["unchanged_control_operation"] = "encode" if variant == "idct" else "decode"
    result["control_interpretation"] = (
        "The other D operation is unchanged semantically by this variant; "
        "compare paired candidate/legacy movement to detect drift. It is not "
        "a frequency lock or proof of equal code generation.")
    if variant == "color":
        raw = (build / f"{case[0]}.raw").read_bytes()
        result["output_comparison"] = {}
        for backend in ("candidate", "legacy"):
            encoded = (build / f"{case[0]}-{(candidate if backend == 'candidate' else legacy).name}.jpg").read_bytes()
            with Image.open(io.BytesIO(encoded)) as image:
                decoded = image.tobytes()
            result["output_comparison"][backend] = {
                "jpeg_sha256": digest(encoded), "jpeg_bytes": len(encoded),
                "error_vs_raw": differences(decoded, raw, len(case[3])),
            }
        with Image.open(build / f"{case[0]}-{candidate.name}.jpg") as image:
            candidate_pixels = image.tobytes()
        with Image.open(build / f"{case[0]}-{legacy.name}.jpg") as image:
            legacy_pixels = image.tobytes()
        result["output_comparison"]["candidate_vs_legacy"] = differences(
            candidate_pixels, legacy_pixels, len(case[3]))
    return result


def run_d(binary, case, folder, save, repeats):
    name, width, height, mode, quality, sampling = case
    image_path = folder / f"{name}-{binary.name}.jpg" if save else "-"
    decoded_path = folder / f"{name}-{binary.name}.raw" if save else "-"
    invocation = ["/usr/bin/time", "-f", "RSS_KIB=%M", str(binary),
                  str(folder / f"{name}.raw"), str(folder / f"{name}-reference.jpg"),
                  str(image_path), str(decoded_path), str(width), str(height),
                  str(len(mode)), str(quality), sampling, "both", str(repeats)]
    frequency_before = cpu_frequency_khz()
    completed = subprocess.run(invocation, text=True, capture_output=True,
                               check=True)
    frequency_after = cpu_frequency_khz()
    fields = completed.stdout.strip().split()
    if len(fields) != 5:
        raise RuntimeError(f"unexpected D benchmark output: {completed.stdout!r}")
    rss = next(int(line.split("=", 1)[1]) for line in
               completed.stderr.splitlines() if line.startswith("RSS_KIB="))
    return {
        "encode_ns": int(fields[0]), "decode_ns": int(fields[1]),
        "encoded_bytes": int(fields[2]), "decode_checksum": int(fields[3]),
        "output_capacity_bytes": int(fields[4]), "rss_peak_kib": rss,
        "cpu_khz_before": frequency_before, "cpu_khz_after": frequency_after,
        "image_path": image_path if save else None,
        "decoded_path": decoded_path if save else None,
    }


def run_pillow(image, reference, quality, sampling, repeats):
    def encode():
        output = io.BytesIO()
        image.save(output, format="JPEG", quality=quality,
                   subsampling={"444": 0, "422": 1, "420": 2}[sampling],
                   progressive=False, optimize=False)
        return output.getvalue()

    def decode():
        with Image.open(io.BytesIO(reference)) as opened:
            return opened.tobytes()

    encode()
    decode()
    frequency_before = cpu_frequency_khz()
    start = time.perf_counter_ns()
    for _ in range(repeats):
        encoded = encode()
    encode_ns = (time.perf_counter_ns() - start) // repeats
    start = time.perf_counter_ns()
    for _ in range(repeats):
        decoded = decode()
    decode_ns = (time.perf_counter_ns() - start) // repeats
    frequency_after = cpu_frequency_khz()
    if encoded != reference:
        raise RuntimeError("Pillow output changed between warm-up and timed run")
    return {
        "encode_ns": encode_ns, "decode_ns": decode_ns,
        "encoded_bytes": len(encoded), "decode_checksum": sum(decoded),
        # The Python orchestrator retains all fixtures and is not a codec RSS
        # measurement. Do not put its peak beside the isolated D processes.
        "rss_peak_kib": None,
        "cpu_khz_before": frequency_before, "cpu_khz_after": frequency_after,
    }


def verify_case(case, folder, first_runs):
    name, width, height, mode, quality, sampling = case
    raw = (folder / f"{name}.raw").read_bytes()
    reference = (folder / f"{name}-reference.jpg").read_bytes()
    with Image.open(io.BytesIO(reference)) as opened:
        reference_pixels = opened.tobytes()
    report = {
        "reference_jpeg_bytes": len(reference),
        "reference_jpeg_sha256": digest(reference),
        "reference_encode_error": differences(reference_pixels, raw, len(mode)),
    }
    compiler_pixels = {}
    compiler_sizes = {}
    for compiler in ("dmd", "ldc2"):
        sample = first_runs[compiler]
        encoded = sample["image_path"].read_bytes()
        decoded = sample["decoded_path"].read_bytes()
        if len(encoded) != sample["encoded_bytes"]:
            raise RuntimeError("D reported encoded length does not match file")
        with Image.open(io.BytesIO(encoded)) as opened:
            opened.load()
            if opened.size != (width, height) or opened.mode != mode:
                raise RuntimeError("D output dimensions/mode do not match fixture")
            pillow_pixels = opened.tobytes()
        magick_pixels = subprocess.run(
            ["magick", str(sample["image_path"]), "-depth", "8",
             "gray:-" if mode == "L" else "rgb:-"],
            check=True, capture_output=True).stdout
        if len(magick_pixels) != len(raw):
            raise RuntimeError("ImageMagick output length does not match fixture")
        if len(decoded) != len(reference_pixels) or sum(decoded) != sample["decode_checksum"]:
            raise RuntimeError("D reference decode length/checksum mismatch")
        report[compiler] = {
            "encoded_sha256": digest(encoded),
            "encode_error": differences(pillow_pixels, raw, len(mode)),
            "pillow_vs_magick": differences(pillow_pixels, magick_pixels,
                                            len(mode)),
            "decode_vs_pillow_same_file": differences(decoded, reference_pixels,
                                                       len(mode)),
        }
        compiler_pixels[compiler] = pillow_pixels
        compiler_sizes[compiler] = len(encoded)
        report[compiler]["decode_sample_equivalent_within_3"] = (
            report[compiler]["decode_vs_pillow_same_file"]["max"] <= 3)
        if not report[compiler]["decode_sample_equivalent_within_3"]:
            raise RuntimeError(
                f"{name} {compiler}: same-file decoder exceeds 3-level oracle tolerance")
    report["compiler_encoded_byte_equal"] = (
        report["dmd"]["encoded_sha256"] == report["ldc2"]["encoded_sha256"])
    report["compiler_decoded_pixel_delta"] = differences(
        compiler_pixels["dmd"], compiler_pixels["ldc2"], len(mode))
    delta = report["compiler_decoded_pixel_delta"]
    if delta["max"] > 4 or delta["mean"] > 0.01 or \
       abs(compiler_sizes["dmd"] - compiler_sizes["ldc2"]) > \
       max(4, compiler_sizes["dmd"] // 1000):
        raise RuntimeError("DMD and LDC encoded semantics disagree")
    return report


def host_info():
    cpu_model = None
    cpu_info = pathlib.Path("/proc/cpuinfo")
    if cpu_info.exists():
        for line in cpu_info.read_text().splitlines():
            if line.startswith("model name"):
                cpu_model = line.split(":", 1)[1].strip()
                break
    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None
    selected_cpu = affinity[0] if affinity else 0
    governor = pathlib.Path(
        f"/sys/devices/system/cpu/cpu{selected_cpu}/cpufreq/scaling_governor")
    return {
        "platform": platform.platform(), "python": platform.python_version(),
        "cpu_model": cpu_model,
        "cpu_governor": governor.read_text().strip() if governor.exists() else None,
        "affinity": affinity,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--inner-repeats", type=int, default=1,
                        help="timed calls per process/sample, averaged; default 1")
    parser.add_argument("--case", action="append", choices=CASES,
                        help="limit to named cases; repeat for multiple cases")
    parser.add_argument("--cpu", type=int, help="pin this process and children")
    parser.add_argument("--corpus-dir", type=pathlib.Path,
                        help="read hash-pinned real sources locally; otherwise download on demand")
    parser.add_argument("--profile", action="store_true",
                        help="also sample LDC encode/decode separately with perf")
    parser.add_argument("--compare-bitwriter", action="store_true",
                        help="paired packed-versus-legacy LDC bitwriter experiment")
    parser.add_argument("--compare-color-transform", action="store_true",
                        help="paired integer-versus-floating LDC color-transform experiment")
    parser.add_argument("--compare-idct", action="store_true",
                        help="paired sparse-versus-dense LDC IDCT experiment")
    parser.add_argument("--output", type=pathlib.Path,
                        help="write the JSON record outside the temporary build")
    parser.add_argument("--workdir", type=pathlib.Path,
                        help="new directory to retain fixtures and binaries for diagnosis")
    args = parser.parse_args()
    if args.rounds < 3:
        parser.error("at least three paired rounds are required")
    if args.inner_repeats < 1 or args.inner_repeats > 100:
        parser.error("inner repeats must be in 1..100")
    if args.cpu is not None:
        if not hasattr(os, "sched_setaffinity"):
            parser.error("CPU affinity is unavailable on this host")
        os.sched_setaffinity(0, {args.cpu})
    selected = [name for name in CASES if (args.case is None and name not in REAL_SOURCES)
                or (args.case is not None and name in args.case)]
    report = {
        "schema": "imageio-d/jpeg-benchmark-v1",
        "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "git_head": command("git", "rev-parse", "HEAD", cwd=REPO),
        "git_dirty": bool(command("git", "status", "--porcelain", cwd=REPO)),
        "host": host_info(),
        "versions": {
            "dmd": command("dmd", "--version").splitlines()[0],
            "ldc2": command("ldc2", "--version").splitlines()[0],
            "pillow": Image.__version__,
            "libjpeg": features.version_codec("jpg"),
            "libjpeg_turbo": features.check_feature("libjpeg_turbo"),
            "imagemagick": command("magick", "-version").splitlines()[0],
        },
        "method": {
            "rounds": args.rounds,
            "inner_repetitions": args.inner_repeats,
            "order": "rotated backend order in each paired case/round",
            "warmup": "one encode and one decode before each timed sample",
            "d_timing": "caller-owned preallocated buffer; codec calls only",
            "pillow_timing": "Image.save(BytesIO) and Image.open(BytesIO).tobytes; allocates",
            "decode_input": "identical Pillow-generated JPEG bytes for both implementations",
            "encode_input": "identical raw pixel bytes; output codecs/sizes may differ",
            "excludes": "startup, compilation, fixture generation, file I/O, oracle, checksum",
            "rss": "D process peak includes preallocated buffers; Python codec RSS omitted because the orchestrator retains all fixtures",
            "qualified": False,
            "reason": "small corpus, different allocation/entropy contracts, no consumer target",
        },
        "cases": {},
        "source_sha256": {
            str(path.relative_to(REPO)): digest(path.read_bytes())
            for path in (ROOT / "source/jpeg_research.d",
                         ROOT / "source/jpeg_benchmark.d",
                         ROOT / "benchmark_suite.py")
        },
    }
    if args.workdir:
        args.workdir.mkdir(parents=True, exist_ok=False)
    workspace = (contextlib.nullcontext(args.workdir) if args.workdir else
                 tempfile.TemporaryDirectory(prefix="imageio-jpeg-benchmark-"))
    with workspace as temp:
        build = pathlib.Path(temp)
        binaries = {}
        for compiler in ("dmd", "ldc2"):
            binaries[compiler], invocation = compile_d(compiler, build)
            report["method"][f"{compiler}_build"] = invocation
            report["method"][f"{compiler}_binary_sha256"] = digest(
                binaries[compiler].read_bytes())
        case_data = {}
        for name in selected:
            width, height, mode, quality, sampling = CASES[name]
            raw = (real_pixels(name, args.corpus_dir) if name in REAL_SOURCES
                   else pixels(name, width, height, mode))
            raw_path = build / f"{name}.raw"
            raw_path.write_bytes(raw)
            image = Image.frombytes(mode, (width, height), raw)
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=quality,
                       subsampling={"444": 0, "422": 1, "420": 2}[sampling],
                       progressive=False, optimize=False)
            reference = output.getvalue()
            (build / f"{name}-reference.jpg").write_bytes(reference)
            case_data[name] = (image, reference)
            report["cases"][name] = {
                "width": width, "height": height, "mode": mode,
                "quality": quality, "sampling": sampling,
                "raw_sha256": digest(raw), "raw_bytes": len(raw),
                "source": REAL_SOURCES.get(name, {"kind": "synthetic"}),
                "samples": {backend: [] for backend in ("dmd", "ldc2", "pillow")},
            }
        for round_index in range(args.rounds):
            for name in selected[round_index % len(selected):] + selected[:round_index % len(selected)]:
                width, height, mode, quality, sampling = CASES[name]
                case = (name, width, height, mode, quality, sampling)
                backends = ["dmd", "pillow", "ldc2"]
                backends = backends[round_index % 3:] + backends[:round_index % 3]
                for backend in backends:
                    if backend == "pillow":
                        sample = run_pillow(*case_data[name], quality, sampling,
                                            args.inner_repeats)
                    else:
                        sample = run_d(binaries[backend], case, build,
                                       save=round_index == 0,
                                       repeats=args.inner_repeats)
                    report["cases"][name]["samples"][backend].append(sample)
            print(f"completed round {round_index + 1}/{args.rounds}", flush=True)
        for name in selected:
            width, height, mode, quality, sampling = CASES[name]
            case_report = report["cases"][name]
            first = {backend: case_report["samples"][backend][0]
                     for backend in ("dmd", "ldc2")}
            case_report["preflight"] = verify_case(
                (name, width, height, mode, quality, sampling), build, first)
            case_report["paired_rounds"] = [
                {backend: {
                    "encode_ms": round(case_report["samples"][backend][index]["encode_ns"] / 1e6, 3),
                    "decode_ms": round(case_report["samples"][backend][index]["decode_ns"] / 1e6, 3),
                    "cpu_khz_before": case_report["samples"][backend][index]["cpu_khz_before"],
                    "cpu_khz_after": case_report["samples"][backend][index]["cpu_khz_after"],
                } for backend in ("dmd", "ldc2", "pillow")}
                for index in range(args.rounds)
            ]
            for backend, samples in case_report["samples"].items():
                case_report[backend] = {
                    "encode": distribution([sample["encode_ns"] for sample in samples]),
                    "decode": distribution([sample["decode_ns"] for sample in samples]),
                    "encoded_bytes": samples[0]["encoded_bytes"],
                    "rss_peak_kib": (max(sample["rss_peak_kib"] for sample in samples)
                                     if backend != "pillow" else None),
                    "decode_checksum": samples[0]["decode_checksum"],
                    "output_capacity_bytes": samples[0].get("output_capacity_bytes"),
                }
                if len({sample["encoded_bytes"] for sample in samples}) != 1 or \
                   len({sample["decode_checksum"] for sample in samples}) != 1:
                    raise RuntimeError(f"nondeterministic bytes/checksum: {name} {backend}")
            case_report["directional_comparison"] = {}
            for compiler in ("dmd", "ldc2"):
                d_report = case_report[compiler]
                pillow_report = case_report["pillow"]
                d_psnr = case_report["preflight"][compiler]["encode_error"]["psnr_db"]
                pillow_psnr = case_report["preflight"]["reference_encode_error"]["psnr_db"]
                case_report["directional_comparison"][compiler] = {
                    "encode_time_ratio": round(d_report["encode"]["median_ms"] /
                                               pillow_report["encode"]["median_ms"], 2),
                    "decode_time_ratio": round(d_report["decode"]["median_ms"] /
                                               pillow_report["decode"]["median_ms"], 2),
                    "encoded_size_ratio": round(d_report["encoded_bytes"] /
                                                pillow_report["encoded_bytes"], 3),
                    "encode_psnr_delta_db": (round(d_psnr - pillow_psnr, 3)
                                             if d_psnr is not None and
                                             pillow_psnr is not None else None),
                    "decode_sample_equivalent_within_3": case_report[
                        "preflight"][compiler]["decode_sample_equivalent_within_3"],
                    "performance_qualified": False,
                }
                for operation in ("encode", "decode"):
                    ratios = [
                        round(case_report["samples"][compiler][index][f"{operation}_ns"] /
                              case_report["samples"]["pillow"][index][f"{operation}_ns"], 2)
                        for index in range(args.rounds)
                    ]
                    case_report["directional_comparison"][compiler][
                        f"paired_{operation}_time_ratios"] = ratios
            del case_report["samples"]
            print(name, "LDC encode/decode ms",
                  case_report["ldc2"]["encode"]["median_ms"],
                  case_report["ldc2"]["decode"]["median_ms"],
                  "Pillow", case_report["pillow"]["encode"]["median_ms"],
                  case_report["pillow"]["decode"]["median_ms"], flush=True)
        if args.profile:
            name = selected[0]
            report["profile"] = {"case": name, **profile_d(
                (name, *CASES[name]), build)}
        if args.compare_bitwriter:
            name = selected[0]
            report["bitwriter_comparison"] = {"case": name, **compare_variant(
                (name, *CASES[name]), build, binaries["ldc2"],
                args.rounds, args.inner_repeats, "bitwriter")}
        if args.compare_color_transform:
            name = selected[0]
            report["color_transform_comparison"] = {"case": name, **compare_variant(
                (name, *CASES[name]), build, binaries["ldc2"],
                args.rounds, args.inner_repeats, "color")}
        if args.compare_idct:
            name = selected[0]
            report["idct_comparison"] = {"case": name, **compare_variant(
                (name, *CASES[name]), build, binaries["ldc2"],
                args.rounds, args.inner_repeats, "idct")}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print("record:", args.output)
    else:
        print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
