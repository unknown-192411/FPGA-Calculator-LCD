# 🖩 FPGA-Based Calculator with LCD Interface

> A hardware calculator built on Xilinx Spartan-3A FPGA using Verilog HDL — featuring a 4×4 matrix keypad, real-time LCD display via ESP32 bridge, and full FSM-based arithmetic logic.

![Status](https://img.shields.io/badge/Status-Completed-brightgreen?style=flat-square)
![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Spartan--3A%20XC3S50A-E01F27?style=flat-square)
![Language](https://img.shields.io/badge/HDL-Verilog-9C27B0?style=flat-square)
![Tool](https://img.shields.io/badge/Tool-Xilinx%20ISE%2014.7-E01F27?style=flat-square)
![Bridge](https://img.shields.io/badge/Bridge-ESP32%20UART--I2C-E7352C?style=flat-square&logo=espressif&logoColor=white)
![Institute](https://img.shields.io/badge/RGIT-Mumbai-1565C0?style=flat-square)
![Year](https://img.shields.io/badge/Academic%20Year-2025--26-orange?style=flat-square)

---

## 👥 Team

| Name | Roll No |
|------|---------|
| Rutuja Vasant Chikne | A617 |
| Kavish Ashok Nishad | A645 |
| Mahendra Prajapati | A650 |
| Nihal Ramesh Vimal | A655 |

**Guide:** Prof. Rahmani Akhtar  
**Department:** Electronics & Telecommunication Engineering, RGIT Mumbai  
**University:** University of Mumbai

---

## 📌 Project Overview

This project implements a fully functional digital calculator on a **Xilinx Spartan-3A (XC3S50A) FPGA** mounted on the Numato Lab Elbert V2 development board. The user enters multi-digit numbers (0–255) via a **4×4 matrix keypad**, the FPGA performs addition and subtraction using a 3-state FSM, and results are displayed on a **16×2 I2C LCD**.

A key design decision is using an **ESP32 as a dedicated UART-to-I2C bridge** — the FPGA transmits an 8-byte binary packet at 9600 baud to the ESP32, which handles the LCD over its native I2C peripheral. This cleanly solves voltage-level incompatibility between the 3.3V FPGA and the 5V-biased PCF8574 LCD backpack.

---

## 🔧 Hardware Components

| Component | Role |
|-----------|------|
| Xilinx Spartan-3A XC3S50A (Elbert V2) | Core processing — FSM, arithmetic, UART TX |
| 4×4 Matrix Keypad | User input — digits and operators |
| ESP32 (WROOM-30P1) | UART-to-I2C bridge — drives LCD |
| 16×2 I2C LCD (PCF8574 backpack) | Output display |

---

## 🏗️ System Architecture

```
4×4 Matrix Keypad
       │
       ▼
FPGA (Spartan-3A XC3S50A)
  ├── keypad_scanner  →  column-scan debounce, key decode
  ├── calculator FSM  →  3-state arithmetic logic
  └── uart_tx         →  8-byte packet @ 9600 baud
       │
       ▼ (single wire: FPGA pin P141 → ESP32 RX)
ESP32 Microcontroller
  ├── UART reception & packet validation
  ├── String formatting (sign, expression)
  └── I2C LCD write (LiquidCrystal_I2C)
       │
       ▼
16×2 I2C LCD Display
  Line 1: "A: 22  B: 6"
  Line 2: "22 + 6 = 28"
```

---

## 🧠 Verilog Modules

### Module 1: `keypad_scanner`
- Drives one column LOW at a time in round-robin (4'b1110 → 1101 → 1011 → 0111)
- Free-running **16-bit timer** overflows every ~5.4 ms at 12 MHz — provides built-in mechanical debounce
- On key press: asserts `key_active`, pulses `key_pressed` for **exactly one clock cycle** (prevents repeated digit entry)
- Decodes row×column into 4-bit `key_val` (0–15)

### Module 2: `calculator` (Top-Level FSM)
3-state FSM with combinational arithmetic:

| State | Name | Description |
|-------|------|-------------|
| 0 | Entering A | Accumulate digits into regA buffer |
| 1 | Entering B | Accumulate digits into regB buffer |
| 2 | Result | Display result; next digit starts fresh |

**Key actions:**
- Digits 0–9: `acc = acc × 10 + digit`, guarded by `next_acc <= 255` (overflow protection)
- Key A (Add): saves accumulator → regA, sets op=1, moves to State 1
- Key B (Subtract): saves accumulator → regA, sets op=2, moves to State 1
- Key D (Equals): saves accumulator → regB, computes result, moves to State 2
- Key C (Clear): resets all registers and FSM to State 0
- **Chain calculation**: pressing A/B in State 2 retains previous result as new regA

**Arithmetic (combinational):**
```verilog
wire [8:0] sum  = regA + regB;
wire [8:0] diff = (regA >= regB) ? (regA - regB) : (regB - regA);
wire is_neg     = (op == 2) && (regA < regB);
wire [8:0] calc_res = (op==1) ? sum : (op==2) ? diff : 0;
```

### Module 3: `uart_tx`
- Standard **8N1 UART**, parameterised at `CLKS_PER_BIT = 1250` → **9600 baud** from 12 MHz clock
- 4-state FSM: Idle → Start bit → 8 Data bits → Stop bit
- Full 8-byte packet transmitted in ≈ 8.3 ms

---

## 📦 UART Packet Format (8 Bytes)

| Byte | Field | Description |
|------|-------|-------------|
| 0 | Start marker | `0xAA` |
| 1 | Operand A | Current regA or live accumulator |
| 2 | Operand B | Current regB or live accumulator |
| 3 | Operator | 00=none, 01=add, 02=subtract |
| 4 | Result high byte | Bit 8 of 9-bit result |
| 5 | Result low byte | Bits 7–0 of 9-bit result |
| 6 | Sign flag | 1 if result is negative |
| 7 | End marker | `0x55` |

Packet is sent on **every key press** — LCD updates in real time as digits are typed.

---

## 📍 Pin Assignments (UCF)

| Net | FPGA Pin | Description |
|-----|----------|-------------|
| `clk` | P129 | 12 MHz system clock |
| `uart_tx_pin` | P141 | UART TX → ESP32 RX |
| `led_ind` | P46 | Key-active indicator LED |
| `kp_row[0–3]` | P10, P11, P7, P8 | Keypad row inputs (PULLUP) |
| `kp_col[0–3]` | P3, P5, P4, P6 | Keypad column outputs |

---

## ✅ Test Results

| Test Case | Expected | Result |
|-----------|----------|--------|
| 100 + 155 | 255 | ✅ Pass |
| 200 + 55 | 255 (max) | ✅ Pass |
| 255 + 1 (overflow guard) | Blocked at 255 | ✅ Pass |
| 200 − 50 | 150 | ✅ Pass |
| 10 − 200 (negative) | −190 | ✅ Pass |
| Chain: (50 + 30) − 20 | 60 | ✅ Pass |
| Press C mid-entry | All registers cleared | ✅ Pass |
| LED on key hold | LED lit while held | ✅ Pass |
| LCD updates on each digit | Live display update | ✅ Pass |

---

## 📊 FPGA Resource Utilisation

| Resource | Used | Available | Utilisation |
|----------|------|-----------|-------------|
| Slice Flip-Flops | ~80 | 3,168 | ~3% |
| 4-input LUTs | ~150 | 3,168 | ~5% |
| Block RAMs | 0 | 3 | 0% |
| DSP/Multiplier Blocks | 0 | 2 | 0% |
| IOBs | 11 | 108 | 10% |

Extremely compact — only 5% LUT usage, leaving full headroom for future extensions like multiplication or division.

---

## 📂 Repository Structure

```
FPGA-Calculator-LCD/
├── verilog/
│   └── finalwkey.v           # All 3 modules: calculator, keypad_scanner, uart_tx
├── constraints/
│   └── finale.ucf            # Pin assignment file for Elbert V2
├── esp32_firmware/
│   └── esp32_lcd_bridge.ino  # ESP32 UART receiver + I2C LCD writer
├── simulation/
│   └── waveforms/            # ISim simulation screenshots
├── docs/
│   ├── block_diagram.png
│   ├── circuit_diagram.png
│   └── project_report.pdf
└── README.md
```

---

## ⚙️ Why ESP32 as a Bridge?

Direct I2C from FPGA was avoided because:
- Spartan-3A uses **push-pull LVCMOS33** I/O — I2C requires open-drain
- PCF8574 backpack operates at 5V — risks damaging 3.3V FPGA pins
- HD44780 LCD initialisation sequence is complex to implement in Verilog FSM
- I2C at 100 kHz is 120× slower than the 12 MHz clock — needs clock-domain crossing logic

The ESP32 solves all of this in firmware using the `LiquidCrystal_I2C` Arduino library.

---

## 🔮 Future Scope

- Add multiplication and division (extend op register + arithmetic logic only)
- Expand operand range beyond 8-bit (255)
- Add memory/recall function
- Port to a larger FPGA for more complex operations

---

## 👨‍💻 Authors

**Mahendra Prajapati** · **Rutuja Chikne** · **Kavish Nishad** · **Nihal Vimal**  
Electronics & Telecommunication Engineering — RGIT Mumbai  
Academic Year 2025–26 · University of Mumbai
