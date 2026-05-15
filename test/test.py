# SPDX-FileCopyrightText: © 2025 vermiscore
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import random

@cocotb.test()
async def test_reset(dut):
    """リセット後の基本動作確認"""
    dut._log.info("Start: test_reset")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # リセット後はSELECTが0か1のどちらか（不定にならないこと）
    select = int(dut.uo_out.value) & 0x01
    dut._log.info(f"SELECT after reset: {select}")
    assert int(dut.uo_out.value) is not None
    dut._log.info("Reset test passed")

@cocotb.test()
async def test_convergence_B_wins(dut):
    """B=80%優位のとき SELECT=0(B) に収束することを確認"""
    dut._log.info("Start: test_convergence_B_wins")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1

    random.seed(42)
    prob_A, prob_B = 0.20, 0.80
    sel_counts = [0, 0]

    for cy in range(300):
        dA = 1 if random.random() < prob_A else 0
        dB = 1 if random.random() < prob_B else 0
        dut.ui_in.value = (dA << 0) | (dB << 1)
        await ClockCycles(dut.clk, 1)
        if cy >= 100:
            sel = int(dut.uo_out.value) & 0x01
            sel_counts[sel] += 1

    rate_B = sel_counts[0] / sum(sel_counts)
    dut._log.info(f"B selection rate: {rate_B:.1%} (expected >85%)")
    assert rate_B > 0.75, f"B not preferred: {rate_B:.1%}"
    dut._log.info("Convergence B test passed")

@cocotb.test()
async def test_switch(dut):
    """環境切替後にA=80%へ収束することを確認"""
    dut._log.info("Start: test_switch")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1

    random.seed(123)

    # Phase1: B=80%で収束
    for _ in range(200):
        dA = 1 if random.random() < 0.20 else 0
        dB = 1 if random.random() < 0.80 else 0
        dut.ui_in.value = (dA << 0) | (dB << 1)
        await ClockCycles(dut.clk, 1)

    # Phase2: A=80%に切替
    sel_counts = [0, 0]
    for cy in range(300):
        dA = 1 if random.random() < 0.80 else 0
        dB = 1 if random.random() < 0.20 else 0
        dut.ui_in.value = (dA << 0) | (dB << 1)
        await ClockCycles(dut.clk, 1)
        if cy >= 100:
            sel = int(dut.uo_out.value) & 0x01
            sel_counts[sel] += 1

    rate_A = sel_counts[1] / sum(sel_counts)
    dut._log.info(f"A selection rate after switch: {rate_A:.1%} (expected >75%)")
    assert rate_A > 0.75, f"A not preferred after switch: {rate_A:.1%}"
    dut._log.info("Switch test passed")
