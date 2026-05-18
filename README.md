# IMG_FILTER Work Area

This directory is a clean workspace for the official digital topic:
`图像滤波 / IMG_FILTER`.

## Layout

- `docs/spec_summary.md`: extracted requirements and implementation notes
- `rtl/img_filter.v`: top-level RTL skeleton
- `rtl/img_filter_def.v`: memory configuration macros
- `rtl/rtl.f`: file list for compile/synthesis
- `tb/`: smoke test, directed regression, and VCS run script

## Current Status

- The formal digital topic appears to be `图像滤波`.
- The separate `实验环境搭建说明` file looks like a support document, not a full second formal topic.
- The embedded attachment inside the official topic document contains the detailed `IMG_FILTER` specification.
- `rtl/img_filter.v` now contains a first-pass implementation with:
  - frame config latch
  - vertical coefficient expansion
  - row-by-row SRAM write
  - row-overlapped input/output scheduling with mirror addressing
  - per-channel MAC and `>> 7` normalization
- `tb/tb_img_filter_smoke.v` passes a `blk_v=1` identity smoke test in VCS.
- `tb/tb_img_filter_directed.v` passes 4 directed cases in VCS:
  - `blk_v=1` identity
  - `blk_v=3` weighted filter
  - width not divisible by 4
  - `blk_v=49` mirror boundary
- `tb/tb_img_filter_regression.v` passes 9 deterministic in-spec cases in VCS:
  - widths `24/25/32/37/40`
  - heights `24/25/27/29/31/64`
  - `blk_v = 1/3/5/7/9/15/49`
  - includes a `height=64, blk_v=49` wrap-stress case

## Current Behavior

- The scheduler no longer pauses all input traffic while emitting a row.
- After enough rows are buffered, input for the next row can proceed while output consumes an older ready row.
- Input overlap is bounded so the 49-row ring buffer does not overwrite still-needed rows.
- The VCS regressions still pass after this refactor.

## Quick Run

- Smoke: `bash tb/run_vcs_img_filter_regression.sh smoke`
- Directed: `bash tb/run_vcs_img_filter_regression.sh directed`
- Regression: `bash tb/run_vcs_img_filter_regression.sh regression`

Each mode now uses its own `/tmp` build directory so runs do not clobber each other.

## Next Suggested Work

1. Add randomized or software-co-sim comparison beyond the current deterministic regression.
2. Rework the phased emit path into a more overlapped pipeline if performance/PPA becomes a bottleneck.
3. Revisit `MEM_NUM` and `MEM_DWTH` after functionality is stable.
