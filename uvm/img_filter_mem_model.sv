`timescale 1ns/1ps
`include "../rtl/img_filter_def.v"

module img_filter_mem_model (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic [`MEM_NUM*1-1:0]         mem_ce,
    input  logic [`MEM_NUM*1-1:0]         mem_we,
    input  logic [`MEM_NUM*11-1:0]        mem_addr,
    input  logic [`MEM_NUM*`MEM_DWTH-1:0] mem_wdata,
    output logic [`MEM_NUM*`MEM_DWTH-1:0] mem_rdata
);

localparam int MEM_DEPTH = 1440;

logic [`MEM_DWTH-1:0] mem_array [0:`MEM_NUM-1][0:MEM_DEPTH-1];

always_ff @(posedge clk or negedge rst_n) begin : mem_model_blk
    int i;
    int a;

    if (!rst_n) begin
        mem_rdata <= '0;
    end else begin
        mem_rdata <= '0;

        for (i = 0; i < `MEM_NUM; i++) begin
            if (mem_ce[i]) begin
                a = mem_addr[(i*11) +: 11];
                if (mem_we[i]) begin
                    mem_array[i][a] <= mem_wdata[(i*`MEM_DWTH) +: `MEM_DWTH];
                end else begin
                    mem_rdata[(i*`MEM_DWTH) +: `MEM_DWTH] <= mem_array[i][a];
                end
            end
        end
    end
end

endmodule
