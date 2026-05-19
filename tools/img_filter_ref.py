#!/usr/bin/env python3
"""Software reference model for IMG_FILTER deterministic cases.

This script mirrors the deterministic data generation rules used by
`tb/tb_img_filter_regression.v` so the repository has a portable golden model
independent of a simulator.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


MAX_HALF_COEF = 25
PIXEL_MASK = (1 << 10) - 1


@dataclass(frozen=True)
class FilterCase:
    name: str
    width: int
    height: int
    blk_v: int
    salt: int
    profile: int


REGRESSION_CASES = [
    FilterCase("regression_case_1", 24, 24, 1, 0, 1),
    FilterCase("regression_case_2", 25, 24, 3, 17, 2),
    FilterCase("regression_case_3", 32, 25, 5, 53, 3),
    FilterCase("regression_case_4", 37, 24, 7, 91, 4),
    FilterCase("regression_case_5", 24, 31, 9, 123, 5),
    FilterCase("regression_case_6", 33, 29, 15, 211, 6),
    FilterCase("regression_case_7", 24, 24, 49, 301, 7),
    FilterCase("regression_case_8", 40, 27, 3, 401, 8),
    FilterCase("regression_case_9", 24, 64, 49, 557, 7),
]


def mirror_row(raw_row: int, img_height: int) -> int:
    tmp = raw_row
    for _ in range(2):
        if tmp < 0:
            tmp = -tmp - 1
        elif tmp >= img_height:
            tmp = (img_height << 1) - 1 - tmp
    return tmp


def pack_pixel(b: int, g: int, r: int, a: int) -> int:
    return (
        ((a & PIXEL_MASK) << 30)
        | ((r & PIXEL_MASK) << 20)
        | ((g & PIXEL_MASK) << 10)
        | (b & PIXEL_MASK)
    )


def make_pixel(row_i: int, col_i: int, salt_i: int) -> int:
    base = (row_i * 41 + col_i * 17 + salt_i) & PIXEL_MASK
    return pack_pixel(base + 0, base + 1, base + 2, base + 3)


def pixel_channel(pixel: int, channel_idx: int) -> int:
    return (pixel >> (channel_idx * 10)) & PIXEL_MASK


def norm_chan(accum_int: int) -> int:
    norm_int = accum_int >> 7
    if norm_int < 0:
        return 0
    if norm_int > PIXEL_MASK:
        return PIXEL_MASK
    return norm_int


def set_coeff_profile(profile_id: int) -> list[int]:
    coef_valid = [0] * MAX_HALF_COEF

    if profile_id == 1:
        coef_valid[0] = 128
    elif profile_id == 2:
        coef_valid[0] = 32
        coef_valid[1] = 64
    elif profile_id == 3:
        coef_valid[0] = 8
        coef_valid[1] = 24
        coef_valid[2] = 64
    elif profile_id == 4:
        coef_valid[0] = 4
        coef_valid[1] = 12
        coef_valid[2] = 20
        coef_valid[3] = 56
    elif profile_id == 5:
        coef_valid[0] = 2
        coef_valid[1] = 4
        coef_valid[2] = 8
        coef_valid[3] = 16
        coef_valid[4] = 68
    elif profile_id == 6:
        coef_valid[0] = 1
        coef_valid[1] = 1
        coef_valid[2] = 2
        coef_valid[3] = 4
        coef_valid[4] = 8
        coef_valid[5] = 12
        coef_valid[6] = 16
        coef_valid[7] = 40
    elif profile_id == 7:
        for i in range(24):
            coef_valid[i] = 2
        coef_valid[24] = 32
    elif profile_id == 8:
        coef_valid[0] = 16
        coef_valid[1] = 96
    else:
        raise ValueError(f"unsupported profile_id={profile_id}")

    return coef_valid


def expand_coeffs(blk_v: int, coef_valid: list[int]) -> list[int]:
    half = (blk_v - 1) // 2
    coef_full: list[int] = []

    for tap_i in range(blk_v):
        coef_delta = abs(tap_i - half)
        coef_idx = half - coef_delta
        coef_full.append(coef_valid[coef_idx])

    if sum(coef_full) != 128:
        raise ValueError(f"expanded coefficient sum is {sum(coef_full)}, expected 128")

    return coef_full


def build_src_pixels(width: int, height: int, salt: int) -> list[list[int]]:
    return [
        [make_pixel(row_i, col_i, salt) for col_i in range(width)]
        for row_i in range(height)
    ]


def pack_word(pixels: Iterable[int]) -> int:
    word = 0
    for lane_i, pixel in enumerate(pixels):
        word |= pixel << (lane_i * 40)
    return word


def build_input_words(src_pixels: list[list[int]]) -> list[int]:
    width = len(src_pixels[0])
    row_words = (width + 3) // 4
    input_words: list[int] = []

    for row in src_pixels:
        for word_i in range(row_words):
            lanes = []
            for lane_i in range(4):
                col_i = word_i * 4 + lane_i
                lanes.append(row[col_i] if col_i < width else 0)
            input_words.append(pack_word(lanes))

    return input_words


def filter_pixel(
    src_pixels: list[list[int]],
    row_i: int,
    col_i: int,
    blk_v: int,
    coef_full: list[int],
) -> int:
    half = (blk_v - 1) // 2
    height = len(src_pixels)
    acc = [0, 0, 0, 0]

    for tap_i in range(blk_v):
        src_row_i = mirror_row(row_i + tap_i - half, height)
        src_pix = src_pixels[src_row_i][col_i]
        for ch_i in range(4):
            acc[ch_i] += pixel_channel(src_pix, ch_i) * coef_full[tap_i]

    return pack_pixel(
        norm_chan(acc[0]),
        norm_chan(acc[1]),
        norm_chan(acc[2]),
        norm_chan(acc[3]),
    )


def build_expected_words(
    src_pixels: list[list[int]],
    blk_v: int,
    coef_full: list[int],
) -> list[int]:
    width = len(src_pixels[0])
    height = len(src_pixels)
    row_words = (width + 3) // 4
    expected_words: list[int] = []

    for row_i in range(height):
        for word_i in range(row_words):
            lanes = []
            for lane_i in range(4):
                col_i = word_i * 4 + lane_i
                if col_i < width:
                    lanes.append(filter_pixel(src_pixels, row_i, col_i, blk_v, coef_full))
                else:
                    lanes.append(0)
            expected_words.append(pack_word(lanes))

    return expected_words


def digest_words(words: list[int]) -> str:
    digest = hashlib.sha256()
    for word in words:
        digest.update(f"{word:040x}\n".encode("ascii"))
    return digest.hexdigest()


def words_to_hex(words: list[int]) -> str:
    return "".join(f"{word:040x}\n" for word in words)


def build_case_payload(case: FilterCase) -> dict:
    coef_valid = set_coeff_profile(case.profile)
    coef_full = expand_coeffs(case.blk_v, coef_valid)
    src_pixels = build_src_pixels(case.width, case.height, case.salt)
    input_words = build_input_words(src_pixels)
    expected_words = build_expected_words(src_pixels, case.blk_v, coef_full)

    return {
        "case": case,
        "coef_valid": coef_valid[: ((case.blk_v - 1) // 2) + 1],
        "coef_full": coef_full,
        "input_words": input_words,
        "expected_words": expected_words,
        "row_words": (case.width + 3) // 4,
        "total_words": ((case.width + 3) // 4) * case.height,
    }


def payload_summary(payload: dict) -> dict:
    case: FilterCase = payload["case"]
    input_words = payload["input_words"]
    expected_words = payload["expected_words"]
    return {
        "name": case.name,
        "width": case.width,
        "height": case.height,
        "blk_v": case.blk_v,
        "salt": case.salt,
        "profile": case.profile,
        "row_words": payload["row_words"],
        "total_words": payload["total_words"],
        "coef_valid": payload["coef_valid"],
        "coef_full_sum": sum(payload["coef_full"]),
        "input_sha256": digest_words(input_words),
        "expected_sha256": digest_words(expected_words),
        "first_input_word": f"{input_words[0]:040x}" if input_words else "",
        "first_expected_word": f"{expected_words[0]:040x}" if expected_words else "",
        "last_expected_word": f"{expected_words[-1]:040x}" if expected_words else "",
    }


def write_case_files(prefix: Path, payload: dict) -> None:
    prefix.parent.mkdir(parents=True, exist_ok=True)
    summary = payload_summary(payload)

    input_path = Path(f"{prefix}.input.hex")
    expected_path = Path(f"{prefix}.expected.hex")
    meta_path = Path(f"{prefix}.meta.json")

    input_path.write_text(words_to_hex(payload["input_words"]), encoding="ascii")
    expected_path.write_text(words_to_hex(payload["expected_words"]), encoding="ascii")
    meta_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="ascii")


def run_case(args: argparse.Namespace) -> int:
    case = FilterCase(
        name=args.name or "custom_case",
        width=args.width,
        height=args.height,
        blk_v=args.blk_v,
        salt=args.salt,
        profile=args.profile,
    )
    payload = build_case_payload(case)
    summary = payload_summary(payload)

    if args.output_prefix:
        write_case_files(Path(args.output_prefix), payload)

    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


def run_regression(args: argparse.Namespace) -> int:
    summaries = []
    output_dir = Path(args.output_dir) if args.output_dir else None

    for case in REGRESSION_CASES:
        payload = build_case_payload(case)
        summaries.append(payload_summary(payload))
        if output_dir is not None:
            write_case_files(output_dir / case.name, payload)

    print(json.dumps({"cases": summaries}, indent=2, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="IMG_FILTER software reference model")
    subparsers = parser.add_subparsers(dest="command")

    case_parser = subparsers.add_parser("case", help="build one custom case")
    case_parser.add_argument("--name", default="custom_case")
    case_parser.add_argument("--width", type=int, required=True)
    case_parser.add_argument("--height", type=int, required=True)
    case_parser.add_argument("--blk-v", type=int, required=True, dest="blk_v")
    case_parser.add_argument("--salt", type=int, required=True)
    case_parser.add_argument("--profile", type=int, required=True)
    case_parser.add_argument("--output-prefix")
    case_parser.set_defaults(func=run_case)

    regression_parser = subparsers.add_parser(
        "regression", help="build all deterministic regression cases"
    )
    regression_parser.add_argument("--output-dir")
    regression_parser.set_defaults(func=run_regression)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if not getattr(args, "command", None):
        parser.print_help()
        return 1

    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
