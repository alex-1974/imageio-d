#!/usr/bin/env python3
"""Locate DMD/LDC JPEG divergence at sample, coefficient and byte levels."""
import argparse
import array
import datetime as dt
import json
import pathlib
import tempfile

from benchmark_suite import CASES, REAL_SOURCES, ROOT, command, digest, real_pixels


def first_difference(left, right, blocks_per_mcu, mcu_columns):
    for index, (a, b) in enumerate(zip(left, right)):
        if a != b:
            block, within = divmod(index, 64)
            mcu, component_block = divmod(block, blocks_per_mcu)
            return {"index": index, "block": block,
                    "coefficient_or_sample": within, "mcu": mcu,
                    "mcu_xy": [mcu % mcu_columns, mcu // mcu_columns],
                    "component_block": component_block,
                    "dmd": a, "ldc2": b}
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=REAL_SOURCES,
                        default="real-landscape-420")
    parser.add_argument("--corpus-dir", type=pathlib.Path)
    parser.add_argument("--float-color", action="store_true",
                        help="reproduce the historical floating RGB-to-YCbCr path")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    width, height, mode, quality, sampling = CASES[args.case]
    raw = real_pixels(args.case, args.corpus_dir)
    h = 1 if sampling == "444" else 2
    v = 2 if sampling == "420" else 1
    mcu_columns = (width + 8 * h - 1) // (8 * h)
    blocks_per_mcu = 1 if mode == "L" else h * v + 2
    report = {"schema": "imageio-d/jpeg-compiler-diagnosis-v1",
              "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "case": args.case, "float_color": args.float_color,
              "source_sha256": REAL_SOURCES[args.case]["sha256"],
              "raw_sha256": digest(raw), "source_code_sha256": digest(
                  (ROOT / "source/jpeg_research.d").read_bytes()),
              "probe_code_sha256": digest(
                  (ROOT / "source/jpeg_coefficient_probe.d").read_bytes()),
              "builds": {}}
    with tempfile.TemporaryDirectory(prefix="imageio-jpeg-compiler-diag-") as temp:
        build = pathlib.Path(temp)
        raw_path = build / "input.raw"
        raw_path.write_bytes(raw)
        samples = {}
        coefficients = {}
        jpegs = {}
        for compiler in ("dmd", "ldc2"):
            flags = ["-O3" if compiler == "ldc2" else "-O", "-release",
                     "-boundscheck=on", "-dip1000"]
            if args.float_color:
                flags.append(("-d-version=" if compiler == "ldc2" else "-version=") +
                             "JpegFloatColorTransform")
            binary = build / f"probe-{compiler}"
            invocation = [compiler, *flags, f"-I={ROOT / 'source'}",
                          f"-of={binary}", str(ROOT / "source/jpeg_research.d"),
                          str(ROOT / "source/jpeg_coefficient_probe.d")]
            command(*invocation)
            report["builds"][compiler] = {"invocation": invocation,
                                           "binary_sha256": digest(binary.read_bytes())}
            jpg = build / f"{compiler}.jpg"
            sample = build / f"{compiler}.samples"
            coeff = build / f"{compiler}.coefficients"
            command(str(binary), str(raw_path), str(width), str(height),
                    str(len(mode)), str(quality), sampling, str(jpg),
                    str(sample), str(coeff))
            samples[compiler] = sample.read_bytes()
            values = array.array("i")
            values.frombytes(coeff.read_bytes())
            coefficients[compiler] = values
            jpegs[compiler] = jpg.read_bytes()
        a, b = samples["dmd"], samples["ldc2"]
        c, d = coefficients["dmd"], coefficients["ldc2"]
        assert len(a) == len(b) == len(c) == len(d)
        report["sample_difference_count"] = sum(x != y for x, y in zip(a, b))
        report["coefficient_difference_count"] = sum(x != y for x, y in zip(c, d))
        report["first_sample_difference"] = first_difference(
            a, b, blocks_per_mcu, mcu_columns)
        report["first_coefficient_difference"] = first_difference(
            c, d, blocks_per_mcu, mcu_columns)
        report["coefficient_differences_with_equal_input_block"] = sum(
            x != y and a[(i // 64) * 64:(i // 64 + 1) * 64] ==
            b[(i // 64) * 64:(i // 64 + 1) * 64]
            for i, (x, y) in enumerate(zip(c, d)))
        report["jpeg_byte_equal"] = jpegs["dmd"] == jpegs["ldc2"]
        report["jpeg_sha256"] = {key: digest(value) for key, value in jpegs.items()}
        report["jpeg_size"] = {key: len(value) for key, value in jpegs.items()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("record:", args.output, "JPEG byte equal:", report["jpeg_byte_equal"])


if __name__ == "__main__":
    main()
