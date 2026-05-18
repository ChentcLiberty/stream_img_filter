# Open-Source Reuse Notes

Shortlist reviewed on `2026-05-18` for reuse potential with this repository.

The key constraint is that this project is not a generic 3x3 image filter. The current target is a custom `IMG_FILTER` with:

- `RGBA`, `10-bit/channel`, `4 pixels/cycle`
- vertical-only filtering with odd `blk_v=1..49`
- mirror boundary handling
- external single-port SRAM row storage
- contest-style stream handshakes

No public repository reviewed here matches that interface and scheduling model exactly, so the realistic reuse strategy is selective reuse rather than full-copy reuse.

## Best Reuse Candidates

### hdl-util/image-processing

- Repo: `https://github.com/hdl-util/image-processing`
- Why it is useful:
  - SystemVerilog image-processing code with clean module boundaries
  - example testbench included in the repository README
  - permissive license setup visible on the repo page
- Best things to reuse:
  - testbench structure
  - parameterization style
  - image-pipeline module organization
- Limits:
  - focused on demosaicing, not this SRAM-backed vertical filter
- License signal seen on repo page:
  - `MIT` and `Apache`

### Gowtham1729/Image-Processing

- Repo: `https://github.com/Gowtham1729/Image-Processing`
- Why it is useful:
  - Verilog image-processing toolbox
  - includes multiple convolution-style operations
  - includes Python scripts for image preprocessing and memory-file generation
- Best things to reuse:
  - image-to-memory preprocessing flow
  - quick software-side test asset generation
  - small convolution examples for sanity comparison
- Limits:
  - BRAM/VGA oriented flow
  - not built around external SRAM handshakes or `4 pixels/cycle`
- License signal seen on repo page:
  - `Apache License 2.0`

### pConst/basic_verilog

- Repo: `https://github.com/pConst/basic_verilog`
- Why it is useful:
  - large utility library with reusable FIFO, RAM, adder-tree, and helper modules
  - mature repository with many stars and broad HDL utility coverage
- Best things to reuse:
  - single-clock FIFO templates
  - RAM templates
  - `adder_tree` style infrastructure if the MAC datapath gets reworked
  - general testbench utilities
- Limits:
  - not image-filter specific
  - share-alike obligations may be undesirable if you want fewer license constraints
- License signal seen on repo page:
  - `CC BY-SA 4.0`

## Good Architecture References, But Check License Before Copying Code

### ykqiu/image-processing

- Repo: `https://github.com/ykqiu/image-processing`
- Why it is useful:
  - pipelined Verilog ISP project
  - includes matrix generation, Gaussian filter, Sobel, SDRAM controller, and display pipeline
  - unusually close to the kind of row-buffer and filtering control patterns you care about
- Best things to borrow conceptually:
  - row/matrix generation ideas
  - off-chip image-buffering architecture ideas
  - staged image-processing pipeline decomposition
- Limits:
  - broader ISP project, not a drop-in match
  - much of the filtering flow is `3x3`-centric
  - no clear permissive license signal was visible on the repo page I reviewed

### georgeyhere/FPGA-Video-Processing

- Repo: `https://github.com/georgeyhere/FPGA-Video-Processing`
- Why it is useful:
  - clearer-than-average documentation for a video filter pipeline
  - documents line-buffer filling and kernel control behavior
  - mixes Gaussian and Sobel stages in a readable top-level flow
- Best things to borrow conceptually:
  - line-buffer control ideas
  - kernel-control decomposition
  - documentation style for block diagrams and dataflow
- Limits:
  - camera/display pipeline oriented
  - framebuffer assumptions differ from this repository
  - no clear permissive license signal was visible on the repo page I reviewed

### Galapple/Image-processing---Verilog

- Repo: `https://github.com/Galapple/Image-processing---Verilog`
- Why it is useful:
  - very small and easy to read
  - exposes `lineBuffer.v`, `conv.v`, and a simple control split
- Best things to borrow conceptually:
  - quick line-buffer sanity reference
  - naming and partition ideas for beginner-friendly modules
- Limits:
  - small student-style project
  - fixed Sobel use case
  - no clear license signal was visible on the repo page I reviewed

## Utility Option If The Project Grows

### open-logic/open-logic

- Repo: `https://github.com/open-logic/open-logic`
- Why it is useful:
  - broad reusable HDL library
  - includes base, AXI, interface, and fixed-point areas
  - explicitly states use from SystemVerilog is possible
- Best things to reuse:
  - generic infrastructure if this repository later grows AXI wrappers, fixed-point helpers, or reusable buses
- Limits:
  - VHDL-first project
  - likely too heavy if you only need a small pure-Verilog contest submission
- License signal seen on repo page:
  - `LGPL with exceptions for FPGA usage`

## Bottom Line

The best practical reuse path for this repository is:

1. Keep the core `IMG_FILTER` datapath and SRAM scheduling custom.
2. Borrow utility modules only where they save time without distorting the current interface.
3. Treat larger public image-processing repos mainly as architecture and verification references.
4. Avoid copying from repos without a clearly stated license.

If I were optimizing for speed right now, I would prioritize:

1. `Gowtham1729/Image-Processing` for software-side test asset generation
2. `pConst/basic_verilog` for optional utility modules
3. `ykqiu/image-processing` for architecture ideas only
