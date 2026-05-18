`timescale 1ns/1ps
`include "./img_filter_def.v"

module IMG_FILTER (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_pix_rdy,
    output wire                         in_pix_need,
    input  wire [159:0]                 in_pix_data,

    output wire                         out_pix_rdy,
    input  wire                         out_pix_need,
    output wire [159:0]                 out_pix_data,

    input  wire                         frm_start,
    input  wire [10:0]                  img_width,
    input  wire [11:0]                  img_height,
    input  wire [5:0]                   blk_v,
    input  wire [25*8-1:0]              coef,

    output wire [`MEM_NUM*1-1:0]        mem_ce,
    output wire [`MEM_NUM*1-1:0]        mem_we,
    output wire [`MEM_NUM*11-1:0]       mem_addr,
    output wire [`MEM_NUM*`MEM_DWTH-1:0] mem_wdata,
    input  wire [`MEM_NUM*`MEM_DWTH-1:0] mem_rdata
);

localparam integer ST_IDLE      = 0;
localparam integer ST_RECV      = 1;
localparam integer ST_EMIT_REQ  = 2;
localparam integer ST_EMIT_RESP = 3;
localparam integer ST_EMIT_HOLD = 4;

localparam integer MAX_TAPS   = 49;
localparam integer SLOT_COUNT = 49;

reg [2:0] state;

reg [10:0] cfg_width_m1;
reg [11:0] cfg_height_m1;
reg [5:0]  cfg_blk_v;
reg [5:0]  cfg_half;
reg [8:0]  cfg_row_words;
reg [2:0]  cfg_last_lanes;

reg [7:0] coef_expanded [0:MAX_TAPS-1];

reg        capture_done;
reg [12:0] completed_rows;
reg [11:0] wr_row_idx;
reg [8:0]  wr_word_idx;
reg [11:0] next_emit_row;
reg [11:0] emit_row_active;
reg [8:0]  emit_word_idx;
reg [8:0]  emit_resp_word_idx;

reg         out_valid_r;
reg [159:0] out_data_r;

reg [`MEM_NUM*1-1:0]         mem_ce_r;
reg [`MEM_NUM*1-1:0]         mem_we_r;
reg [`MEM_NUM*11-1:0]        mem_addr_r;
reg [`MEM_NUM*`MEM_DWTH-1:0] mem_wdata_r;

reg [159:0] emit_data_c;

// First-pass implementation assumption:
// use one 160-bit memory word per 4-pixel beat and one logical row per SRAM slot.
// This matches the default starter macros in img_filter_def.v.

wire        in_pix_hs;
wire        out_pix_hs;
wire        frame_active;
wire        emit_row_valid_idx;
wire        emit_follow_row_valid_idx;
wire        emit_row_ready;
wire        emit_follow_row_ready;
wire [12:0] buffered_rows_ahead;
wire [12:0] max_buffered_rows_ahead;
wire        input_window_ok;

assign in_pix_hs = in_pix_rdy & in_pix_need;
assign out_pix_hs = out_valid_r & out_pix_need;
assign frame_active = (state != ST_IDLE);
assign emit_row_valid_idx = ({1'b0, next_emit_row} <= {1'b0, cfg_height_m1});
assign emit_follow_row_valid_idx = (({1'b0, next_emit_row} + 13'd1) <= {1'b0, cfg_height_m1});
assign emit_row_ready =
    emit_row_valid_idx &&
    (capture_done || ((({1'b0, next_emit_row} + {7'd0, cfg_half}) + 13'd1) <= completed_rows));
assign emit_follow_row_ready =
    emit_follow_row_valid_idx &&
    (capture_done || ((({1'b0, next_emit_row} + {7'd0, cfg_half}) + 13'd2) <= completed_rows));
assign buffered_rows_ahead = completed_rows - {1'b0, next_emit_row};
assign max_buffered_rows_ahead = 13'd49 - {7'd0, cfg_half};
assign input_window_ok = (buffered_rows_ahead < max_buffered_rows_ahead);

assign in_pix_need = frame_active & (~capture_done) & input_window_ok;
assign out_pix_rdy = out_valid_r;
assign out_pix_data = out_data_r;

assign mem_ce = mem_ce_r;
assign mem_we = mem_we_r;
assign mem_addr = mem_addr_r;
assign mem_wdata = mem_wdata_r;

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

function integer tap_slot;
    input integer emit_row_int;
    input integer tap_idx_int;
    input integer half_int;
    input integer img_height_int;
    integer src_row_int;
begin
    src_row_int = mirror_row(emit_row_int + tap_idx_int - half_int, img_height_int);
    tap_slot = src_row_int % SLOT_COUNT;
end
endfunction

function [39:0] pixel_lane;
    input [159:0] word160;
    input integer lane_idx_int;
begin
    case (lane_idx_int)
        0: pixel_lane = word160[39:0];
        1: pixel_lane = word160[79:40];
        2: pixel_lane = word160[119:80];
        default: pixel_lane = word160[159:120];
    endcase
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

always @* begin : mem_ctrl_blk
    integer tap_i;
    integer slot_i;
    integer emit_row_int;
    integer img_height_int;

    mem_ce_r = {`MEM_NUM{1'b0}};
    mem_we_r = {`MEM_NUM{1'b0}};
    mem_addr_r = {(`MEM_NUM*11){1'b0}};
    mem_wdata_r = {(`MEM_NUM*`MEM_DWTH){1'b0}};

    if (in_pix_hs) begin
        slot_i = wr_row_idx % SLOT_COUNT;
        if (slot_i < `MEM_NUM) begin
            mem_ce_r[slot_i] = 1'b1;
            mem_we_r[slot_i] = 1'b1;
            mem_addr_r[(slot_i*11) +: 11] = wr_word_idx;
            mem_wdata_r[(slot_i*`MEM_DWTH) +: `MEM_DWTH] = in_pix_data;
        end
    end

    if (state == ST_EMIT_REQ) begin
        emit_row_int = emit_row_active;
        img_height_int = cfg_height_m1 + 1;

        for (tap_i = 0; tap_i < MAX_TAPS; tap_i = tap_i + 1) begin
            if (tap_i < cfg_blk_v) begin
                slot_i = tap_slot(emit_row_int, tap_i, cfg_half, img_height_int);
                if (slot_i < `MEM_NUM) begin
                    mem_ce_r[slot_i] = 1'b1;
                    mem_addr_r[(slot_i*11) +: 11] = emit_word_idx;
                end
            end
        end
    end
end

always @* begin : emit_data_blk
    integer lane_i;
    integer tap_i;
    integer slot_i;
    integer acc_b;
    integer acc_g;
    integer acc_r;
    integer acc_a;
    integer img_height_int;
    integer emit_row_int;
    reg [159:0] src_word;
    reg [39:0]  src_pixel;

    emit_data_c = 160'b0;
    img_height_int = cfg_height_m1 + 1;
    emit_row_int = emit_row_active;

    for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
        if ((emit_resp_word_idx == (cfg_row_words - 1'b1)) &&
            (lane_i >= cfg_last_lanes)) begin
            emit_data_c[(lane_i*40) +: 40] = 40'b0;
        end else begin
            acc_b = 0;
            acc_g = 0;
            acc_r = 0;
            acc_a = 0;

            for (tap_i = 0; tap_i < MAX_TAPS; tap_i = tap_i + 1) begin
                if (tap_i < cfg_blk_v) begin
                    slot_i = tap_slot(emit_row_int, tap_i, cfg_half, img_height_int);
                    src_word = mem_rdata[(slot_i*160) +: 160];
                    src_pixel = pixel_lane(src_word, lane_i);

                    acc_b = acc_b + (src_pixel[9:0]   * coef_expanded[tap_i]);
                    acc_g = acc_g + (src_pixel[19:10] * coef_expanded[tap_i]);
                    acc_r = acc_r + (src_pixel[29:20] * coef_expanded[tap_i]);
                    acc_a = acc_a + (src_pixel[39:30] * coef_expanded[tap_i]);
                end
            end

            emit_data_c[(lane_i*40) +: 40] = {
                norm_chan(acc_a),
                norm_chan(acc_r),
                norm_chan(acc_g),
                norm_chan(acc_b)
            };
        end
    end
end

always @(posedge clk or negedge rst_n) begin : seq_blk
    integer coef_i;
    integer coef_delta;
    integer coef_idx;
    if (!rst_n) begin
        state <= ST_IDLE;

        cfg_width_m1 <= 11'd0;
        cfg_height_m1 <= 12'd0;
        cfg_blk_v <= 6'd0;
        cfg_half <= 6'd0;
        cfg_row_words <= 9'd0;
        cfg_last_lanes <= 3'd0;

        capture_done <= 1'b0;
        completed_rows <= 13'd0;
        wr_row_idx <= 12'd0;
        wr_word_idx <= 9'd0;
        next_emit_row <= 12'd0;
        emit_row_active <= 12'd0;
        emit_word_idx <= 9'd0;
        emit_resp_word_idx <= 9'd0;

        out_valid_r <= 1'b0;
        out_data_r <= 160'b0;

        for (coef_i = 0; coef_i < MAX_TAPS; coef_i = coef_i + 1) begin
            coef_expanded[coef_i] <= 8'd0;
        end
    end else begin
        if (frame_active && in_pix_hs) begin
            if (wr_word_idx == (cfg_row_words - 1'b1)) begin
                wr_word_idx <= 9'd0;
                completed_rows <= completed_rows + 13'd1;

                if (wr_row_idx == cfg_height_m1) begin
                    capture_done <= 1'b1;
                end else begin
                    wr_row_idx <= wr_row_idx + 1'b1;
                end
            end else begin
                wr_word_idx <= wr_word_idx + 1'b1;
            end
        end

        case (state)
            ST_IDLE: begin
                out_valid_r <= 1'b0;
                out_data_r <= 160'b0;
                capture_done <= 1'b0;
                completed_rows <= 13'd0;

                if (frm_start) begin
                    cfg_width_m1 <= img_width;
                    cfg_height_m1 <= img_height;
                    cfg_blk_v <= blk_v;
                    cfg_half <= (blk_v - 1'b1) >> 1;
                    cfg_row_words <= ({1'b0, img_width} + 12'd4) >> 2;
                    cfg_last_lanes <= {1'b0, img_width[1:0]} + 3'd1;

                    wr_row_idx <= 12'd0;
                    wr_word_idx <= 9'd0;
                    completed_rows <= 13'd0;
                    next_emit_row <= 12'd0;
                    emit_row_active <= 12'd0;
                    emit_word_idx <= 9'd0;
                    emit_resp_word_idx <= 9'd0;

                    for (coef_i = 0; coef_i < MAX_TAPS; coef_i = coef_i + 1) begin
                        if (coef_i < blk_v) begin
                            if (coef_i > ((blk_v - 1'b1) >> 1)) begin
                                coef_delta = coef_i - ((blk_v - 1'b1) >> 1);
                            end else begin
                                coef_delta = ((blk_v - 1'b1) >> 1) - coef_i;
                            end
                            coef_idx = ((blk_v - 1'b1) >> 1) - coef_delta;
                            coef_expanded[coef_i] <= coef[(coef_idx*8) +: 8];
                        end else begin
                            coef_expanded[coef_i] <= 8'd0;
                        end
                    end

                    state <= ST_RECV;
                end
            end

            ST_RECV: begin
                if (emit_row_ready) begin
                    emit_row_active <= next_emit_row;
                    emit_word_idx <= 9'd0;
                    emit_resp_word_idx <= 9'd0;
                    state <= ST_EMIT_REQ;
                end
            end

            ST_EMIT_REQ: begin
                emit_resp_word_idx <= emit_word_idx;
                state <= ST_EMIT_RESP;
            end

            ST_EMIT_RESP: begin
                out_data_r <= emit_data_c;
                out_valid_r <= 1'b1;
                state <= ST_EMIT_HOLD;
            end

            ST_EMIT_HOLD: begin
                if (out_pix_hs) begin
                    out_valid_r <= 1'b0;

                    if (emit_resp_word_idx == (cfg_row_words - 1'b1)) begin
                        if (next_emit_row == cfg_height_m1) begin
                            next_emit_row <= next_emit_row + 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            next_emit_row <= next_emit_row + 1'b1;

                            if (emit_follow_row_ready) begin
                                emit_row_active <= next_emit_row + 1'b1;
                                emit_word_idx <= 9'd0;
                                emit_resp_word_idx <= 9'd0;
                                state <= ST_EMIT_REQ;
                            end else begin
                                state <= ST_RECV;
                            end
                        end
                    end else begin
                        emit_word_idx <= emit_word_idx + 1'b1;
                        state <= ST_EMIT_REQ;
                    end
                end
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
