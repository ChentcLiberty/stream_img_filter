`timescale 1ns/1ps
`include "../rtl/img_filter_def.v"

module tb_img_filter_uvm_top;

  import uvm_pkg::*;
  import img_filter_pkg::*;

  logic clk;

  img_filter_if vif(clk);

  logic [`MEM_NUM*1-1:0]          mem_ce;
  logic [`MEM_NUM*1-1:0]          mem_we;
  logic [`MEM_NUM*11-1:0]         mem_addr;
  logic [`MEM_NUM*`MEM_DWTH-1:0]  mem_wdata;
  logic [`MEM_NUM*`MEM_DWTH-1:0]  mem_rdata;

  IMG_FILTER dut (
      .clk(clk),
      .rst_n(vif.rst_n),
      .in_pix_rdy(vif.in_pix_rdy),
      .in_pix_need(vif.in_pix_need),
      .in_pix_data(vif.in_pix_data),
      .out_pix_rdy(vif.out_pix_rdy),
      .out_pix_need(vif.out_pix_need),
      .out_pix_data(vif.out_pix_data),
      .frm_start(vif.frm_start),
      .img_width(vif.img_width),
      .img_height(vif.img_height),
      .blk_v(vif.blk_v),
      .coef(vif.coef),
      .mem_ce(mem_ce),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata)
  );

  img_filter_mem_model mem_model (
      .clk(clk),
      .rst_n(vif.rst_n),
      .mem_ce(mem_ce),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    vif.rst_n = 1'b0;
    vif.in_pix_rdy = 1'b0;
    vif.in_pix_data = '0;
    vif.out_pix_need = 1'b1;
    vif.frm_start = 1'b0;
    vif.img_width = '0;
    vif.img_height = '0;
    vif.blk_v = '0;
    vif.coef = '0;

    repeat (4) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual img_filter_if)::set(null, "*", "vif", vif);
    uvm_root::get().set_timeout(5ms, 1);
    run_test();
  end

endmodule
