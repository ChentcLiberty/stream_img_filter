# IMG_FILTER Architecture Outline

## Goal

Get to a functionally correct, synthesizable first version before chasing PPA.

## Recommended Bring-Up Strategy

Use `MEM_DWTH=160` first.

Reason:

- One SRAM word naturally matches `4 pixels/cycle`
- Addressing is simpler than `40` or `80`
- Easier to debug line rotation and row alignment

After correctness is stable, compare against `80` for possible area/power benefit.

## Top-Level Partition

### 1. Config Register Block

Latch the following on `frm_start`:

- `img_width`
- `img_height`
- `blk_v`
- `coef`

Also expand the symmetric coefficients into a local `49 x 8` register view.

### 2. Input Stream Writer

Responsibilities:

- Accept `in_pix_data` on `in_pix_rdy & in_pix_need`
- Track `x` and `y` write position
- Write packed 4-pixel words into external SRAM
- Maintain a rotating row-buffer map

### 3. Window Row Scheduler

Responsibilities:

- For each output row, generate the `blk_v` source row indices
- Apply vertical mirror mapping
- Convert logical source row index into current SRAM row slot

### 4. SRAM Read Controller

Responsibilities:

- Read the required words for the current output position
- Handle single-port conflict between write side and read side
- Prefer a simple phase split first:
  - input fill phase
  - compute/output phase

This is not the best throughput architecture, but it is the safest first bring-up.

### 5. Pixel Window Extractor

Responsibilities:

- Select the target pixel lane from each returned 160-bit word
- Build the vertical tap vector for one output pixel
- Repeat for 4 pixel lanes

### 6. MAC Array

Responsibilities:

- Run 4 parallel pixel computations
- Each pixel computes `R/G/B/A` independently
- Accumulator width should be chosen conservatively first, then trimmed later

### 7. Output Pack Block

Responsibilities:

- Register output data
- Drive `out_pix_rdy`
- Hold data stable while `out_pix_need=0`

## First Functional Version

A pragmatic first version is:

1. Receive one full row into the selected SRAM slot
2. Once enough future rows exist, pause input and emit one output row
3. Resume input and repeat until the frame tail, then flush remaining rows

Advantages:

- Very simple control
- Easy mirror handling
- Easy to verify against software reference

Disadvantage:

- Latency is higher
- Throughput is lower than a fully overlapped streaming design
- PPA may be worse than a streaming-overlap solution

For this contest, this is still a sensible first milestone because functional pass is mandatory before PPA counts.

## Current Verification

- `vlogan -full64` compile passes on the current RTL
- `tb_img_filter_smoke.v` passes the `blk_v=1` identity case in VCS
- `tb_img_filter_directed.v` passes:
  - `blk_v=1` identity
  - `blk_v=3` weighted filter
  - width not divisible by 4
  - `blk_v=49` mirror boundary
- `tb_img_filter_regression.v` passes 9 deterministic in-spec cases across:
  - width range `24` to `40`
  - height range `24` to `64`
  - `blk_v` values `1/3/5/7/9/15/49`
  - includes a ring-buffer wrap stress case at `height=64, blk_v=49`

## Current Scheduler Update

The implementation has already moved beyond the strictly row-serialized first pass:

- input write progress now continues during output phases
- output rows still only start when their newest required source row is fully buffered
- overlap is bounded by the 49-row storage window so wrapped row slots are not overwritten too early
- this preserves single-port SRAM safety while reducing end-to-end frame time

## Second Version Direction

After the full-frame version is stable:

- overlap input and compute where possible
- reduce redundant SRAM reads
- shrink memory count if line reuse can be improved
- review whether `MEM_DWTH=80` gives better balance

## Verification Bring-Up Order

1. `blk_v=1`
2. `blk_v=3`
3. small height with mirror hit at top
4. small height with mirror hit at bottom
5. width not divisible by 4
6. maximum-ish `blk_v=49`
