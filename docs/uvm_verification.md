# UVM Verification

This repository now includes a first-pass UVM environment under `uvm/`.

## Current Scope

The current UVM setup is intentionally narrow:

- one active agent
- one frame sequence item per test
- driver for config pulse and input stream traffic
- monitor for output stream collection
- scoreboard that compares the DUT output against prebuilt expected words
- external SRAM kept as a simple module-level memory model, same idea as the non-UVM testbenches

This is enough to establish a real UVM bring-up baseline without changing the DUT.

## Current Status

Validated in VCS on `2026-05-19` with:

- `CASE_ID=1` (`24x24`, `blk_v=1`)
- `CASE_ID=7` (`24x24`, `blk_v=49`)

## Files

- `uvm/img_filter_if.sv`: DUT-facing interface
- `uvm/img_filter_mem_model.sv`: external SRAM model
- `uvm/img_filter_pkg.sv`: sequence item, sequence, driver, monitor, agent, env, scoreboard, test
- `uvm/tb_img_filter_uvm_top.sv`: top module
- `uvm/run_vcs_img_filter_uvm.sh`: VCS compile/run script

## Run

From repository root:

```bash
bash uvm/run_vcs_img_filter_uvm.sh
```

Choose a deterministic built-in case with `CASE_ID`:

```bash
CASE_ID=1 bash uvm/run_vcs_img_filter_uvm.sh
CASE_ID=7 bash uvm/run_vcs_img_filter_uvm.sh
CASE_ID=9 bash uvm/run_vcs_img_filter_uvm.sh
```

The default is `CASE_ID=1`.

Supported deterministic case IDs currently match the existing regression set:

- `1`: `24x24`, `blk_v=1`
- `2`: `25x24`, `blk_v=3`
- `3`: `32x25`, `blk_v=5`
- `4`: `37x24`, `blk_v=7`
- `5`: `24x31`, `blk_v=9`
- `6`: `33x29`, `blk_v=15`
- `7`: `24x24`, `blk_v=49`
- `8`: `40x27`, `blk_v=3`
- `9`: `24x64`, `blk_v=49`

## What Is Not Done Yet

- constrained-random sequence generation
- functional coverage
- input backpressure randomization on `out_pix_need`
- multi-frame runs in one simulation
- file-driven replay using the Python reference model outputs

Those are the next reasonable extensions if you want the environment to become a fuller verification platform rather than a UVM smoke baseline.
