# Reference Model

`tools/img_filter_ref.py` is a Python software reference for the deterministic
`IMG_FILTER` cases used by `tb/tb_img_filter_regression.v`.

The script intentionally mirrors the Verilog testbench rules for:

- `make_pixel()` source generation
- coefficient profiles
- vertical mirror mapping
- `RGBA` channel packing
- `>> 7` normalization

This gives the repository a portable golden model that does not depend on VCS.

## Quick Usage

Run all built-in deterministic regression cases and print summaries:

```bash
python3 tools/img_filter_ref.py regression
```

Generate all built-in deterministic cases and dump vectors under `ref_vectors/`:

```bash
python3 tools/img_filter_ref.py regression --output-dir ref_vectors
```

Generate one custom case:

```bash
python3 tools/img_filter_ref.py case \
  --name demo_case \
  --width 25 \
  --height 24 \
  --blk-v 3 \
  --salt 17 \
  --profile 2 \
  --output-prefix ref_vectors/demo_case
```

## Generated Files

When `--output-prefix` or `--output-dir` is used, the script writes:

- `*.input.hex`: one packed `160-bit` input word per line
- `*.expected.hex`: one packed `160-bit` expected output word per line
- `*.meta.json`: case summary, dimensions, coefficient info, and SHA256 digests

## Current Scope

This reference model is aligned with the current deterministic regression flow.
It is not yet wired into the Verilog testbench through file-based replay, but it
already provides:

- a simulator-independent golden generator
- reusable vector export for future testbenches
- stable digests for regression bookkeeping
