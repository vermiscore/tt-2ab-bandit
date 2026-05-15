/*
 * Copyright (c) 2025 vermiscore
 * SPDX-License-Identifier: Apache-2.0
 *
 * Two-Armed Bandit Digital Chip
 * 論文: "A 1.8-V 840-MHz Analog Integrated Circuit for the Two-Armed
 *        Bandit Problem in a 180-nm CMOS Technology"
 * のアナログ回路をデジタルで再実装
 *
 * TinyTapeout I/O マッピング:
 *   ui_in[0]   = d_A      (Arm-A result: 1=Win, 0=Lose)
 *   ui_in[1]   = d_B      (Arm-B result: 1=Win, 0=Lose)
 *   ui_in[5:2] = cfg      (DELTA step size, 1LSB=1mV, default=40)
 *   ui_in[6]   = seed_ld  (LFSR seed load strobe)
 *   ui_in[7]   = seed_dat (LFSR seed serial data)
 *
 *   uo_out[0]  = SELECT   (1=Arm-A, 0=Arm-B)
 *   uo_out[1]  = SELECT_N (complement)
 *   uo_out[2]  = PHASE    (0=COMPARE, 1=LEARN)
 *   uo_out[3]  = VALID    (1-cycle pulse: SELECT settled)
 *   uo_out[7:4]= V_th[11:8] (HAC upper bits, debug)
 *
 *   uio_out[7:0] = V_th[7:0] (HAC lower bits, debug)
 *   uio_oe       = 8'hFF     (all output)
 *
 *   clk  = system clock (up to 500 MHz target)
 *   rst_n = async reset, active-low
 */

`default_nettype none

// ============================================================
//  tt_um_2ab_bandit  —  TinyTapeout top module
// ============================================================
module tt_um_2ab_bandit (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ── 入力 ──
    wire        d_A      = ui_in[0];
    wire        d_B      = ui_in[1];
    wire [3:0]  cfg      = ui_in[5:2];   // DELTA設定 (1LSB=1mV)
    wire        seed_ld  = ui_in[6];
    wire        seed_dat = ui_in[7];

    // ── コア出力 ──
    wire        SELECT;
    wire        phase_out;
    wire        valid;
    wire [11:0] V_th_out;

    // ── コアインスタンス ──
    two_armed_bandit_core core (
        .clk      (clk),
        .rst_n    (rst_n),
        .d_A      (d_A),
        .d_B      (d_B),
        .cfg      (cfg),
        .seed_ld  (seed_ld),
        .seed_dat (seed_dat),
        .SELECT   (SELECT),
        .phase_out(phase_out),
        .valid    (valid),
        .V_th_out (V_th_out)
    );

    // ── 出力マッピング ──
    assign uo_out[0]   = SELECT;
    assign uo_out[1]   = ~SELECT;
    assign uo_out[2]   = phase_out;
    assign uo_out[3]   = valid;
    assign uo_out[7:4] = V_th_out[11:8];  // debug upper

    assign uio_out = V_th_out[7:0];       // debug lower
    assign uio_oe  = 8'hFF;               // all output

    // unused
    wire _unused = &{ena, uio_in};

endmodule


// ============================================================
//  two_armed_bandit_core  —  合成可能コア RTL
//
//  論文アナログ回路との対応:
//    HAC (Charge Pump)      → 12-bit signed accumulator V_th
//    Dynamic Comparator     → combinational comparator
//    Thompson Sampling V_CS → LFSR 16-bit pseudo-random
//    Pulse Generator        → 2-phase FSM (COMPARE / LEARN)
//
//  パラメータ:
//    DELTA (cfg pins): 1LSB=1mV, default cfg=0 → 40mV
//    V_MID = 900mV, V_MAX = 1800mV
// ============================================================
module two_armed_bandit_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        d_A,
    input  wire        d_B,
    input  wire [3:0]  cfg,       // DELTA offset: DELTA = 40 + cfg*4 [mV]
    input  wire        seed_ld,   // LFSR seed load (posedge)
    input  wire        seed_dat,  // LFSR seed serial (MSB first, 16 clk)

    output reg         SELECT,
    output wire        phase_out,
    output reg         valid,
    output wire [11:0] V_th_out
);
    localparam W     = 12;
    localparam V_MAX = 12'd1800;
    localparam V_MID = 12'd900;

    // ── DELTA: cfg=0→40mV, cfg=15→100mV ──
    wire [6:0] DELTA = 7'd40 + {3'b0, cfg};

    // ──────────────────────────────────────
    // 1. 2-Phase FSM  (COMPARE=0 / LEARN=1)
    // ──────────────────────────────────────
    reg phase;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) phase <= 1'b0;
        else        phase <= ~phase;
    assign phase_out = phase;

    // ──────────────────────────────────────
    // 2. LFSR 16-bit  (V_CS 相当)
    //    多項式: x^16+x^15+x^13+x^4+1
    // ──────────────────────────────────────
    reg  [15:0] lfsr;
    reg  [3:0]  seed_cnt;
    wire [15:0] lfsr_next = {lfsr[14:0],
                              lfsr[15]^lfsr[14]^lfsr[12]^lfsr[3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr     <= 16'hACE1;
            seed_cnt <= 4'd0;
        end else if (seed_ld) begin
            lfsr     <= {lfsr[14:0], seed_dat};
            seed_cnt <= seed_cnt + 1'b1;
        end else begin
            lfsr <= lfsr_next;
        end
    end

    // lfsr[8:0] → ±256mV → V_MID±256  (論文: ±200mV)
    wire signed [12:0] noise  = {1'b0, lfsr[8:0]} - 13'sd256;
    wire signed [12:0] V_CS_s = $signed({1'b0, V_MID}) + noise;
    wire [W-1:0] V_CS =
        (V_CS_s < 0)                        ? 12'd0   :
        (V_CS_s > $signed({1'b0, V_MAX}))   ? V_MAX   :
                                               V_CS_s[W-1:0];

    reg [W-1:0] V_CS_reg;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)              V_CS_reg <= V_MID;
        else if (phase == 1'b0)  V_CS_reg <= V_CS;   // COMPARE phase でサンプル

    // ──────────────────────────────────────
    // 3. HAC Accumulator  (Charge Pump 相当)
    //    論文 Table 1 の充放電ロジック
    // ──────────────────────────────────────
    reg [W-1:0] V_th;
    assign V_th_out = V_th;

    wire do_discharge = (SELECT & d_A) | (~SELECT & ~d_B);
    wire do_charge    = (~SELECT & d_B) | (SELECT & ~d_A);

    wire signed [W:0] V_th_next_s =
        do_discharge ? ($signed({1'b0, V_th}) - $signed({7'b0, DELTA})) :
        do_charge    ? ($signed({1'b0, V_th}) + $signed({7'b0, DELTA})) :
                       $signed({1'b0, V_th});

    wire [W-1:0] V_th_next =
        (V_th_next_s < 0)                      ? 12'd0  :
        (V_th_next_s > $signed({1'b0, V_MAX})) ? V_MAX  :
                                                  V_th_next_s[W-1:0];

    always @(posedge clk or negedge rst_n)
        if (!rst_n)             V_th <= V_MID;
        else if (phase == 1'b1) V_th <= V_th_next;  // LEARN phase で更新

    // ──────────────────────────────────────
    // 4. Comparator + SELECT + VALID
    // ──────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            SELECT <= 1'b0;
            valid  <= 1'b0;
        end else if (phase == 1'b0) begin  // COMPARE phase
            SELECT <= (V_th < V_CS_reg) ? 1'b1 : 1'b0;
            valid  <= 1'b1;
        end else begin
            valid  <= 1'b0;               // LEARN phase は無効
        end
    end

endmodule
`default_nettype wire
