`timescale 1ns/1ps

`include "../rtl/img_filter_def.v"

module tb_img_filter_smoke;

localparam integer MEM_NUM_TB = `MEM_NUM;
localparam integer MEM_DWTH_TB = `MEM_DWTH;
localparam integer MEM_DEPTH_TB = 1440;

localparam integer IMG_W = 8;
localparam integer IMG_H = 24;
localparam integer ROW_WORDS = IMG_W / 4;
localparam integer TOTAL_WORDS = ROW_WORDS * IMG_H;

reg clk;
reg rst_n;

reg         in_pix_rdy;
wire        in_pix_need;
reg [159:0] in_pix_data;

wire        out_pix_rdy;
reg         out_pix_need;
wire [159:0] out_pix_data;

reg         frm_start;
reg [10:0]  img_width;
reg [11:0]  img_height;
reg [5:0]   blk_v;
reg [25*8-1:0] coef;

wire [`MEM_NUM*1-1:0]         mem_ce;
wire [`MEM_NUM*1-1:0]         mem_we;
wire [`MEM_NUM*11-1:0]        mem_addr;
wire [`MEM_NUM*`MEM_DWTH-1:0] mem_wdata;
reg  [`MEM_NUM*`MEM_DWTH-1:0] mem_rdata;

reg [159:0] mem_array [0:MEM_NUM_TB-1][0:MEM_DEPTH_TB-1];
reg [159:0] expected_words [0:TOTAL_WORDS-1];

integer in_word_idx;
integer out_word_idx;
integer lane_idx;
integer mem_idx;
integer addr_idx;

IMG_FILTER dut (
    .clk(clk),
    .rst_n(rst_n),
    .in_pix_rdy(in_pix_rdy),
    .in_pix_need(in_pix_need),
    .in_pix_data(in_pix_data),
    .out_pix_rdy(out_pix_rdy),
    .out_pix_need(out_pix_need),
    .out_pix_data(out_pix_data),
    .frm_start(frm_start),
    .img_width(img_width),
    .img_height(img_height),
    .blk_v(blk_v),
    .coef(coef),
    .mem_ce(mem_ce),
    .mem_we(mem_we),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata)
);

always #5 clk = ~clk;

always @(posedge clk or negedge rst_n) begin : mem_model_blk
    integer i;
    integer a;
    if (!rst_n) begin
        mem_rdata <= {(`MEM_NUM*`MEM_DWTH){1'b0}};
    end else begin
        mem_rdata <= {(`MEM_NUM*`MEM_DWTH){1'b0}};
        for (i = 0; i < MEM_NUM_TB; i = i + 1) begin
            if (mem_ce[i]) begin
                a = mem_addr[(i*11) +: 11];
                if (mem_we[i]) begin
                    mem_array[i][a] <= mem_wdata[(i*MEM_DWTH_TB) +: MEM_DWTH_TB];
                end else begin
                    mem_rdata[(i*MEM_DWTH_TB) +: MEM_DWTH_TB] <= mem_array[i][a];
                end
            end
        end
    end
end

always @(posedge clk) begin
    if (rst_n && in_pix_rdy && in_pix_need) begin
        in_word_idx = in_word_idx + 1;
    end

    if (rst_n && out_pix_rdy && out_pix_need) begin
        if (out_pix_data !== expected_words[out_word_idx]) begin
            $display("ERROR: output mismatch at word %0d", out_word_idx);
            $display("  expect = %040h", expected_words[out_word_idx]);
            $display("  actual = %040h", out_pix_data);
            $finish;
        end

        out_word_idx = out_word_idx + 1;
        if (out_word_idx == TOTAL_WORDS) begin
            $display("PASS: blk_v=1 identity smoke test passed.");
            $finish;
        end
    end
end

always @(negedge clk) begin
    if (!rst_n) begin
        in_pix_rdy = 1'b0;
        in_pix_data = 160'b0;
    end else if (in_word_idx < TOTAL_WORDS) begin
        if (in_pix_need) begin
            in_pix_rdy = 1'b1;
            in_pix_data = expected_words[in_word_idx];
        end else begin
            in_pix_rdy = 1'b0;
            in_pix_data = 160'b0;
        end
    end else begin
        in_pix_rdy = 1'b0;
        in_pix_data = 160'b0;
    end
end

initial begin : stim_blk
    integer row_idx;
    integer word_idx;
    integer base_pix;
    integer pix_idx;
    reg [39:0] pix_word [0:3];
    reg [159:0] packed_word;

    clk = 1'b0;
    rst_n = 1'b0;
    out_pix_need = 1'b1;
    frm_start = 1'b0;
    img_width = IMG_W - 1;
    img_height = IMG_H - 1;
    blk_v = 6'd1;
    coef = {25{8'd0}};
    coef[7:0] = 8'd128;

    in_word_idx = 0;
    out_word_idx = 0;

    for (mem_idx = 0; mem_idx < MEM_NUM_TB; mem_idx = mem_idx + 1) begin
        for (addr_idx = 0; addr_idx < MEM_DEPTH_TB; addr_idx = addr_idx + 1) begin
            mem_array[mem_idx][addr_idx] = 160'b0;
        end
    end

    for (row_idx = 0; row_idx < IMG_H; row_idx = row_idx + 1) begin
        for (word_idx = 0; word_idx < ROW_WORDS; word_idx = word_idx + 1) begin
            for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                pix_idx = row_idx * IMG_W + word_idx * 4 + lane_idx;
                base_pix = pix_idx & 10'h3ff;
                pix_word[lane_idx] = {
                    (base_pix + 10'd3) & 10'h3ff,
                    (base_pix + 10'd2) & 10'h3ff,
                    (base_pix + 10'd1) & 10'h3ff,
                    (base_pix + 10'd0) & 10'h3ff
                };
            end
            packed_word = {pix_word[3], pix_word[2], pix_word[1], pix_word[0]};
            expected_words[row_idx * ROW_WORDS + word_idx] = packed_word;
        end
    end

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;

    @(posedge clk);
    frm_start <= 1'b1;
    @(posedge clk);
    frm_start <= 1'b0;

    repeat (4000) @(posedge clk);
    $display("ERROR: timeout waiting for all output words.");
    $finish;
end

endmodule
