`timescale 1ns/1ps

`include "../rtl/img_filter_def.v"

module tb_img_filter_directed;

localparam integer MEM_NUM_TB   = `MEM_NUM;
localparam integer MEM_DWTH_TB  = `MEM_DWTH;
localparam integer MEM_DEPTH_TB = 1440;

localparam integer MAX_W         = 16;
localparam integer MAX_H         = 32;
localparam integer MAX_TOTAL_W   = ((MAX_W + 3) / 4) * MAX_H;
localparam integer MAX_TAPS      = 49;
localparam integer MAX_HALF_COEF = 25;

reg clk;
reg rst_n;

reg          in_pix_rdy;
wire         in_pix_need;
reg  [159:0] in_pix_data;

wire         out_pix_rdy;
reg          out_pix_need;
wire [159:0] out_pix_data;

reg            frm_start;
reg [10:0]     img_width;
reg [11:0]     img_height;
reg [5:0]      blk_v;
reg [25*8-1:0] coef;

wire [`MEM_NUM*1-1:0]          mem_ce;
wire [`MEM_NUM*1-1:0]          mem_we;
wire [`MEM_NUM*11-1:0]         mem_addr;
wire [`MEM_NUM*`MEM_DWTH-1:0]  mem_wdata;
reg  [`MEM_NUM*`MEM_DWTH-1:0]  mem_rdata;

reg [159:0] mem_array [0:MEM_NUM_TB-1][0:MEM_DEPTH_TB-1];

reg [39:0]  src_pixels [0:MAX_H-1][0:MAX_W-1];
reg [159:0] input_words [0:MAX_TOTAL_W-1];
reg [159:0] expected_words [0:MAX_TOTAL_W-1];
reg [7:0]   coef_valid [0:MAX_HALF_COEF-1];
reg [7:0]   coef_full [0:MAX_TAPS-1];

integer cur_width;
integer cur_height;
integer cur_blk_v;
integer cur_half;
integer cur_row_words;
integer cur_total_words;

integer in_word_idx;
integer out_word_idx;
integer case_idx;
integer mem_idx;
integer addr_idx;

reg case_done;

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

function integer mirror_row;
    input integer raw_row;
    input integer img_height_int;
    integer tmp;
begin
    tmp = raw_row;

    if (tmp < 0) begin
        tmp = -tmp - 1;
    end else if (tmp >= img_height_int) begin
        tmp = (img_height_int << 1) - 1 - tmp;
    end

    if (tmp < 0) begin
        tmp = -tmp - 1;
    end else if (tmp >= img_height_int) begin
        tmp = (img_height_int << 1) - 1 - tmp;
    end

    mirror_row = tmp;
end
endfunction

function [39:0] make_pixel;
    input integer row_i;
    input integer col_i;
    input integer salt_i;
    integer base;
begin
    base = (row_i * 37 + col_i * 13 + salt_i) & 10'h3ff;
    make_pixel = {
        (base + 10'd3) & 10'h3ff,
        (base + 10'd2) & 10'h3ff,
        (base + 10'd1) & 10'h3ff,
        (base + 10'd0) & 10'h3ff
    };
end
endfunction

function [9:0] norm_chan;
    input integer accum_int;
    integer norm_int;
begin
    norm_int = accum_int >>> 7;

    if (norm_int < 0) begin
        norm_chan = 10'd0;
    end else if (norm_int > 1023) begin
        norm_chan = 10'h3ff;
    end else begin
        norm_chan = norm_int[9:0];
    end
end
endfunction

task clear_mem_model;
    integer i;
    integer a;
begin
    for (i = 0; i < MEM_NUM_TB; i = i + 1) begin
        for (a = 0; a < MEM_DEPTH_TB; a = a + 1) begin
            mem_array[i][a] = 160'b0;
        end
    end
end
endtask

task clear_case_arrays;
    integer i;
    integer r;
    integer c;
begin
    for (i = 0; i < MAX_TOTAL_W; i = i + 1) begin
        input_words[i] = 160'b0;
        expected_words[i] = 160'b0;
    end

    for (i = 0; i < MAX_HALF_COEF; i = i + 1) begin
        coef_valid[i] = 8'd0;
    end

    for (i = 0; i < MAX_TAPS; i = i + 1) begin
        coef_full[i] = 8'd0;
    end

    for (r = 0; r < MAX_H; r = r + 1) begin
        for (c = 0; c < MAX_W; c = c + 1) begin
            src_pixels[r][c] = 40'b0;
        end
    end
end
endtask

task fill_pixels;
    input integer width_i;
    input integer height_i;
    input integer salt_i;
    integer r;
    integer c;
begin
    for (r = 0; r < height_i; r = r + 1) begin
        for (c = 0; c < width_i; c = c + 1) begin
            src_pixels[r][c] = make_pixel(r, c, salt_i);
        end
    end
end
endtask

task build_reference;
    integer i;
    integer row_i;
    integer col_i;
    integer word_i;
    integer lane_i;
    integer tap_i;
    integer coef_idx;
    integer coef_delta;
    integer src_row_i;
    integer acc_b;
    integer acc_g;
    integer acc_r;
    integer acc_a;
    reg [39:0] src_pix;
    reg [159:0] packed_word;
begin
    cur_half = (cur_blk_v - 1) / 2;
    cur_row_words = (cur_width + 3) / 4;
    cur_total_words = cur_row_words * cur_height;

    for (i = 0; i < MAX_TAPS; i = i + 1) begin
        if (i < cur_blk_v) begin
            if (i > cur_half) begin
                coef_delta = i - cur_half;
            end else begin
                coef_delta = cur_half - i;
            end
            coef_idx = cur_half - coef_delta;
            coef_full[i] = coef_valid[coef_idx];
        end else begin
            coef_full[i] = 8'd0;
        end
    end

    coef = {25{8'd0}};
    for (i = 0; i < MAX_HALF_COEF; i = i + 1) begin
        coef[(i*8) +: 8] = coef_valid[i];
    end

    for (row_i = 0; row_i < cur_height; row_i = row_i + 1) begin
        for (word_i = 0; word_i < cur_row_words; word_i = word_i + 1) begin
            packed_word = 160'b0;

            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                col_i = word_i * 4 + lane_i;
                if (col_i < cur_width) begin
                    packed_word[(lane_i*40) +: 40] = src_pixels[row_i][col_i];
                end
            end

            input_words[row_i * cur_row_words + word_i] = packed_word;
        end
    end

    for (row_i = 0; row_i < cur_height; row_i = row_i + 1) begin
        for (word_i = 0; word_i < cur_row_words; word_i = word_i + 1) begin
            packed_word = 160'b0;

            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                col_i = word_i * 4 + lane_i;
                if (col_i < cur_width) begin
                    acc_b = 0;
                    acc_g = 0;
                    acc_r = 0;
                    acc_a = 0;

                    for (tap_i = 0; tap_i < cur_blk_v; tap_i = tap_i + 1) begin
                        src_row_i = mirror_row(row_i + tap_i - cur_half, cur_height);
                        src_pix = src_pixels[src_row_i][col_i];

                        acc_b = acc_b + (src_pix[9:0]   * coef_full[tap_i]);
                        acc_g = acc_g + (src_pix[19:10] * coef_full[tap_i]);
                        acc_r = acc_r + (src_pix[29:20] * coef_full[tap_i]);
                        acc_a = acc_a + (src_pix[39:30] * coef_full[tap_i]);
                    end

                    packed_word[(lane_i*40) +: 40] = {
                        norm_chan(acc_a),
                        norm_chan(acc_r),
                        norm_chan(acc_g),
                        norm_chan(acc_b)
                    };
                end
            end

            expected_words[row_i * cur_row_words + word_i] = packed_word;
        end
    end
end
endtask

task prepare_case_identity;
begin
    clear_case_arrays;
    cur_width = 8;
    cur_height = 24;
    cur_blk_v = 1;
    fill_pixels(cur_width, cur_height, 0);
    coef_valid[0] = 8'd128;
    build_reference;
end
endtask

task prepare_case_blk3;
begin
    clear_case_arrays;
    cur_width = 8;
    cur_height = 24;
    cur_blk_v = 3;
    fill_pixels(cur_width, cur_height, 17);
    coef_valid[0] = 8'd32;
    coef_valid[1] = 8'd64;
    build_reference;
end
endtask

task prepare_case_width10_blk3;
begin
    clear_case_arrays;
    cur_width = 10;
    cur_height = 24;
    cur_blk_v = 3;
    fill_pixels(cur_width, cur_height, 53);
    coef_valid[0] = 8'd16;
    coef_valid[1] = 8'd96;
    build_reference;
end
endtask

task prepare_case_mirror49;
    integer i;
begin
    clear_case_arrays;
    cur_width = 5;
    cur_height = 24;
    cur_blk_v = 49;
    fill_pixels(cur_width, cur_height, 91);
    for (i = 0; i < 24; i = i + 1) begin
        coef_valid[i] = 8'd2;
    end
    coef_valid[24] = 8'd32;
    build_reference;
end
endtask

task pulse_reset;
begin
    rst_n = 1'b0;
    frm_start = 1'b0;
    in_pix_rdy = 1'b0;
    in_pix_data = 160'b0;
    out_pix_need = 1'b1;
    in_word_idx = 0;
    out_word_idx = 0;
    case_done = 1'b0;
    mem_rdata = {(`MEM_NUM*`MEM_DWTH){1'b0}};
    clear_mem_model;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
end
endtask

task run_current_case;
    input integer timeout_cycles;
    integer wait_i;
begin
    pulse_reset;

    img_width = cur_width - 1;
    img_height = cur_height - 1;
    blk_v = cur_blk_v[5:0];

    @(negedge clk);
    frm_start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    frm_start = 1'b0;

    wait_i = 0;
    while ((!case_done) && (wait_i < timeout_cycles)) begin
        @(posedge clk);
        wait_i = wait_i + 1;
    end

    if (!case_done) begin
        $display("ERROR: timeout in case %0d", case_idx);
        $finish;
    end
end
endtask

always @(posedge clk or negedge rst_n) begin : mem_model_blk
    integer i;
    integer a;
begin
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
end

always @(posedge clk) begin
    if (rst_n && in_pix_rdy && in_pix_need) begin
        in_word_idx = in_word_idx + 1;
    end

    if (rst_n && out_pix_rdy && out_pix_need) begin
        if (out_pix_data !== expected_words[out_word_idx]) begin
            $display("ERROR: mismatch in case %0d at output word %0d", case_idx, out_word_idx);
            $display("  expect = %040h", expected_words[out_word_idx]);
            $display("  actual = %040h", out_pix_data);
            $finish;
        end

        out_word_idx = out_word_idx + 1;
        if (out_word_idx == cur_total_words) begin
            case_done = 1'b1;
        end
    end
end

always @(negedge clk) begin
    if (!rst_n) begin
        in_pix_rdy = 1'b0;
        in_pix_data = 160'b0;
    end else if (in_word_idx < cur_total_words) begin
        if (in_pix_need) begin
            in_pix_rdy = 1'b1;
            in_pix_data = input_words[in_word_idx];
        end else begin
            in_pix_rdy = 1'b0;
            in_pix_data = 160'b0;
        end
    end else begin
        in_pix_rdy = 1'b0;
        in_pix_data = 160'b0;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    in_pix_rdy = 1'b0;
    in_pix_data = 160'b0;
    out_pix_need = 1'b1;
    frm_start = 1'b0;
    img_width = 11'd0;
    img_height = 12'd0;
    blk_v = 6'd0;
    coef = {25{8'd0}};
    mem_rdata = {(`MEM_NUM*`MEM_DWTH){1'b0}};

    prepare_case_identity;
    case_idx = 1;
    run_current_case(12000);
    $display("PASS: case %0d identity blk_v=1", case_idx);

    prepare_case_blk3;
    case_idx = 2;
    run_current_case(12000);
    $display("PASS: case %0d blk_v=3 weighted filter", case_idx);

    prepare_case_width10_blk3;
    case_idx = 3;
    run_current_case(16000);
    $display("PASS: case %0d width-not-divisible-by-4", case_idx);

    prepare_case_mirror49;
    case_idx = 4;
    run_current_case(30000);
    $display("PASS: case %0d mirror boundary blk_v=49", case_idx);

    $display("PASS: all directed IMG_FILTER cases passed.");
    $finish;
end

endmodule
