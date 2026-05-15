## How it works

This project is a digital reimplementation of the analog two-armed bandit (2AB) decision-making circuit from the paper "A 1.8-V 840-MHz Analog Integrated Circuit for the Two-Armed Bandit Problem in a 180-nm CMOS Technology" (Mori et al., Meiji University / NICT).

The design implements Thompson sampling for the 2-armed bandit problem using four main blocks:

1. **2-Phase FSM** (Pulse Generator equivalent): alternates between COMPARE and LEARN phases every clock cycle.
2. **16-bit LFSR** (Thompson Sampling V_CS equivalent): generates pseudo-random noise around V_DD/2 (900 mV) to implement exploration.
3. **12-bit HAC Accumulator** (Charge Pump equivalent): updates V_th based on the selected arm's reward signal (Table 1 of the paper).
4. **Comparator + SELECT register**: compares V_th with V_CS to determine which arm to select next.

The chip converges to the better arm within ~64-72 clock cycles after an environment change.

## How to test

1. Assert rst_n low for 4 cycles to reset (V_th initializes to 900 mV).
2. Each clock cycle: set d_A (ui_in[0]) and d_B (ui_in[1]) with 1=Win / 0=Lose.
3. Read SELECT on uo_out[0]: 1=choose Arm-A, 0=choose Arm-B.
4. VALID (uo_out[3]) pulses high when SELECT is settled.
5. Monitor V_th on uo_out[7:4] (upper 4 bits) and uio_out[7:0] (lower 8 bits).

Example: Set d_B=1 (B always wins) for 200 cycles. SELECT should settle to 0 (B). Then swap to d_A=1. SELECT should switch to 1 (A) within ~70 cycles.

## External hardware

None required.
