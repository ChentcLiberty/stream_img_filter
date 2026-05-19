interface img_filter_if(input logic clk);

  logic rst_n;

  logic         in_pix_rdy;
  logic         in_pix_need;
  logic [159:0] in_pix_data;

  logic         out_pix_rdy;
  logic         out_pix_need;
  logic [159:0] out_pix_data;

  logic            frm_start;
  logic [10:0]     img_width;
  logic [11:0]     img_height;
  logic [5:0]      blk_v;
  logic [25*8-1:0] coef;

endinterface
