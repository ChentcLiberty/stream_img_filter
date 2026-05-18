`timescale 1ns/1ps

`include "../rtl/img_filter_def.v"

module tb_img_filter_regression;

localparam integer MEM_NUM_TB   = `MEM_NUM;
localparam integer MEM_DWTH_TB  = `MEM_DWTH;
localparam integer MEM_DEPTH_TB = 1440;

localparam integer MAX_W         = 40;
localparam integer MAX_H         = 72;
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

reg             frm_start;
reg [10:0]      img_width;
reg [11:0]      img_height;
reg [5:0]       blk_v;
reg [25*8-1:0]  coef;

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
    base = (row_i * 41 + col_i * 17 + salt_i) & 10'h3ff;
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

task set_coeff_profile;
    input integer profile_id;
    integer i;
begin
    for (i = 0; i < MAX_HALF_COEF; i = i + 1) begin
        coef_valid[i] = 8'd0;
    end

    case (profile_id)
        1: begin
            coef_valid[0] = 8'd128;
        end
        2: begin
            coef_valid[0] = 8'd32;
            coef_valid[1] = 8'd64;
        end
        3: begin
            coef_valid[0] = 8'd8;
            coef_valid[1] = 8'd24;
            coef_valid[2] = 8'd64;
        end
        4: begin
            coef_valid[0] = 8'd4;
            coef_valid[1] = 8'd12;
            coef_valid[2] = 8'd20;
            coef_valid[3] = 8'd56;
        end
        5: begin
            coef_valid[0] = 8'd2;
            coef_valid[1] = 8'd4;
            coef_valid[2] = 8'd8;
            coef_valid[3] = 8'd16;
            coef_valid[4] = 8'd68;
        end
        6: begin
            coef_valid[0] = 8'd1;
            coef_valid[1] = 8'd1;
            coef_valid[2] = 8'd2;
            coef_valid[3] = 8'd4;
            coef_valid[4] = 8'd8;
            coef_valid[5] = 8'd12;
            coef_valid[6] = 8'd16;
            coef_valid[7] = 8'd40;
        end
        7: begin
            for (i = 0; i < 24; i = i + 1) begin
                coef_valid[i] = 8'd2;
            end
            coef_valid[24] = 8'd32;
        end
        8: begin
            coef_valid[0] = 8'd16;
            coef_valid[1] = 8'd96;
        end
        default: begin
            coef_valid[0] = 8'd128;
        end
    endcase
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

task prepare_case;
    input integer width_i;
    input integer height_i;
    input integer blk_v_i;
    input integer salt_i;
    input integer profile_id;
begin
    clear_case_arrays;
    cur_width = width_i;
    cur_height = height_i;
    cur_blk_v = blk_v_i;
    fill_pixels(cur_width, cur_height, salt_i);
    set_coeff_profile(profile_id);
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
        $display("ERROR: timeout in regression case %0d", case_idx);
        $finish;
    end
end
endtask

always @(posedge clk or negedge rst_n)
begin : mem_model_blk
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
            $display("ERROR: mismatch in regression case %0d at output word %0d", case_idx, out_word_idx);
            $display("  width=%0d height=%0d blk_v=%0d", cur_width, cur_height, cur_blk_v);
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

    prepare_case(24, 24, 1,   0,   1);
    case_idx = 1;
    run_current_case(40000);
    $display("PASS: regression case %0d width=24 height=24 blk_v=1", case_idx);

    prepare_case(25, 24, 3,   17,  2);
    case_idx = 2;
    run_current_case(50000);
    $display("PASS: regression case %0d width=25 height=24 blk_v=3", case_idx);

    prepare_case(32, 25, 5,   53,  3);
    case_idx = 3;
    run_current_case(60000);
    $display("PASS: regression case %0d width=32 height=25 blk_v=5", case_idx);

    prepare_case(37, 24, 7,   91,  4);
    case_idx = 4;
    run_current_case(70000);
    $display("PASS: regression case %0d width=37 height=24 blk_v=7", case_idx);

    prepare_case(24, 31, 9,   123, 5);
    case_idx = 5;
    run_current_case(80000);
    $display("PASS: regression case %0d width=24 height=31 blk_v=9", case_idx);

    prepare_case(33, 29, 15,  211, 6);
    case_idx = 6;
    run_current_case(100000);
    $display("PASS: regression case %0d width=33 height=29 blk_v=15", case_idx);

    prepare_case(24, 24, 49,  301, 7);
    case_idx = 7;
    run_current_case(140000);
    $display("PASS: regression case %0d width=24 height=24 blk_v=49", case_idx);

    prepare_case(40, 27, 3,   401, 8);
    case_idx = 8;
    run_current_case(70000);
    $display("PASS: regression case %0d width=40 height=27 blk_v=3", case_idx);

    prepare_case(24, 64, 49,  557, 7);
    case_idx = 9;
    run_current_case(260000);
    $display("PASS: regression case %0d width=24 height=64 blk_v=49 wrap stress", case_idx);

    $display("PASS: all deterministic IMG_FILTER regression cases passed.");
    $finish;
end

endmodule
