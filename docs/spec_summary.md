# IMG_FILTER Spec Summary

## Problem

Design top module `IMG_FILTER` for streaming image filtering.

- Input image format: `RGBA`
- Per-pixel width: `40` bits
- Per-channel width: `10` bits
- Throughput target: `4 pixels/cycle`
- Input scan order: left-to-right, top-to-bottom

## Image Range

- Width: `24` to `1440` pixels
- Height: `24` to `4096` pixels
- Width and height stay constant within one frame

## Filter Window

- Horizontal block size `blk_h` is fixed to `1`
- Vertical block size `blk_v` is odd and ranges `1` to `49`
- The reference block is centered on the output pixel
- Out-of-bound rows use vertical mirror mapping

## Coefficients

- Up to `49` taps total
- Coefficients are center-symmetric
- External interface provides at most `25` coefficients
- Each coefficient is `8` bits unsigned
- Sum of all expanded valid coefficients is `128`
- Coefficients stay unchanged within one frame

## Deliverables

- `img_filter.v`
- `img_filter_def.v`
- `rtl.f`
- design document

## External Memory Constraints

- External memory is single-port SRAM only
- Depth per memory: `1440`
- Allowed widths: `40`, `80`, `160`
- Allowed memory count: `<=49`
- PPA scoring includes memory area/power impact

## RTL Constraints

- Internal cache uses `reg`; do not infer internal memory or latch
- Avoid long stalls; the environment flags abnormal behavior if both input and output stay without handshake for more than `20000` cycles
- Most input config/data ports require `REG_IN`
- `out_pix_data` requires `REG_OUT`

## Interface Summary

- Input stream:
  - `in_pix_rdy`
  - `in_pix_need`
  - `in_pix_data[159:0]`
- Output stream:
  - `out_pix_rdy`
  - `out_pix_need`
  - `out_pix_data[159:0]`
- Frame/config:
  - `frm_start`
  - `img_width[10:0]` with actual width = value + 1
  - `img_height[11:0]` with actual height = value + 1
  - `blk_v[5:0]`
  - `coef[199:0]`
- SRAM:
  - `mem_ce`
  - `mem_we`
  - `mem_addr`
  - `mem_wdata`
  - `mem_rdata`

## Synthesis Notes From Attachment

- Reference synthesis environment mentions `N7+`
- Target clock is `1 GHz`
- Functional pass is mandatory before PPA score counts

## Recommended First Architecture

Start with a correctness-first architecture:

1. Register all frame configuration on `frm_start`
2. Store incoming rows into external SRAM in a simple row-rotating scheme
3. Generate mirrored row indices for the `blk_v` window
4. Read required source rows into a local register window
5. Expand symmetric coefficients internally
6. Run per-channel MAC and normalization
7. Pack four output pixels back to `out_pix_data`

Only after the path is correct, tune `MEM_NUM` and `MEM_DWTH` for PPA.
