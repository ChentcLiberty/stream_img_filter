# IMG Filter RTL

Verilog RTL for a streaming `IMG_FILTER` design with SRAM-backed row buffering, vertical symmetric filtering, and mirror-boundary handling.

The current codebase is a correctness-first implementation for the digital image-filter topic. It focuses on getting a clean functional baseline in place before pushing harder on timing, area, and power.

## Highlights

- `RGBA`, `10-bit/channel`, `40-bit/pixel`
- `4 pixels/cycle` stream packing
- Vertical filter only: `blk_h=1`, `blk_v=1..49` and odd
- Center-symmetric coefficients with normalized sum `128`
- Vertical mirror mapping for top and bottom boundaries
- External single-port SRAM row storage
- Row-overlapped input/output scheduling with bounded ring-buffer protection

## Repository Layout

- `rtl/img_filter.v`: top-level RTL implementation
- `rtl/img_filter_def.v`: memory configuration macros
- `rtl/rtl.f`: RTL file list
- `tb/tb_img_filter_smoke.v`: minimal identity smoke test
- `tb/tb_img_filter_directed.v`: focused directed cases
- `tb/tb_img_filter_regression.v`: deterministic in-spec regression
- `tb/run_vcs_img_filter_regression.sh`: VCS build and run script
- `docs/spec_summary.md`: condensed specification notes
- `docs/arch_outline.md`: implementation and scheduling notes

## Verification

Run from repository root:

```bash
bash tb/run_vcs_img_filter_regression.sh smoke
bash tb/run_vcs_img_filter_regression.sh directed
bash tb/run_vcs_img_filter_regression.sh regression
```

Each mode uses its own `/tmp` build directory, so repeated runs do not clobber one another.

Current regression status:

- `smoke`: PASS
- `directed`: PASS
- `regression`: PASS

Covered cases include:

- `blk_v = 1/3/5/7/9/15/49`
- width not divisible by `4`
- mirror-boundary handling
- ring-buffer wrap stress at `height=64, blk_v=49`

## Implementation Notes

The present RTL is built around a pragmatic first baseline:

- frame configuration is latched on `frm_start`
- coefficients are expanded into a full symmetric tap view
- input rows are packed into SRAM-backed rotating row slots
- output rows start only after their newest required source row is fully buffered
- overlap is throttled so the `49`-row storage window is never overwritten too early
- per-pixel channel results are normalized with `>> 7`

The main implementation target today is the simple, debug-friendly configuration:

- `MEM_DWTH = 160`
- `MEM_NUM  = 49`

## Next Work

- add randomized or software-reference checking beyond the deterministic regression
- pipeline the MAC-heavy path to reduce timing pressure
- revisit `MEM_DWTH` and memory organization for better PPA
