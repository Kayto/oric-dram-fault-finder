# ORIC DRAM Fault Finder

A diagnostic ROM for identifying faulty DRAM chips in ORIC computers.

![ORIC Atmos](https://img.shields.io/badge/Platform-ORIC%20Atmos-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

The ORIC 48K uses eight 4164 DRAM chips (64Kbit × 1). Each chip handles one bit of the 8-bit data bus. So when you write a byte to memory, each of the 8 chips stores just one bit of that byte.

Sounds simple enough. But a chip might work fine when cold, pass a quick test, then start playing up when things warm up. Or it might only fail under specific patterns where adjacent bits interact. This is happening for me...fun times.

When a single chip fails, it causes errors on a specific data bit. In theory, this allows identification of the faulty IC under work. A "walking bit" test - where we test one bit at a time ($01, $02, $04... $80) - can isolate which chip is misbehaving.

If multiple bits fail together? That's trickier. Could be multiple bad chips? Or points to something else - data bus issues, timing problems, dodgy connections. The tests try to distinguish between these cases.

That's the theory anyway! 

## What is it?

- **Auto-running 16K ROM** - No keyboard input required, starts testing immediately on power-up
- **Continuous loop testing** - Cycles through all tests each pass, runs forever until fault detected
- **Chip identification** - Aims to identify specific faulty IC (IC12-IC19) on single-bit failures
- **Runs test patterns** - Walking bit, AA55, FF00, and address pattern tests
- **Detailed fault display** - Shows address, expected/actual values, binary diff, and test name and potential failure

## Warning

Old computers break when you stress them. Please don't leave this running. On this basis I would not recommend running these tests for long periods on those that work. If it ain't broke don't fix it!

## DRAM Chip Mapping

| Data Bit | DRAM Chip | Data Bit | DRAM Chip |
|----------|-----------|----------|-----------|
| D7 (MSB) | IC12      | D3       | IC16      |
| D6       | IC13      | D2       | IC17      |
| D5       | IC14      | D1       | IC18      |
| D4       | IC15      | D0 (LSB) | IC19      |


## Test Patterns

| Pattern | Values | Purpose |
|---------|--------|---------|
| **Walking Bit** | $01, $02, $04, $08, $10, $20, $40, $80 | Tests one bit at a time to isolate individual DRAM chips |
| **AA55 Pattern** | %10101010 / %01010101 | Tests adjacent bit coupling and refresh issues |
| **FF00 Pattern** | All bits high / all bits low | Tests stuck-high and stuck-low faults |
| **Address Pattern** | Page XOR offset | Tests address line faults and cell uniqueness |

## Fault Display

When a fault is detected, the display shows:

```
ORIC DRAM FAULT FINDER
*** FAULT DETECTED! ***
ADDR: $4032
EXP: $AA  ACT: $2A
DIFF: $80  %10000000
BAD CHIP: IC12 (D7)
FAIL ON PASS: 0033
TEST: AA55 PATTERN
```

### Display Fields

| Field | Description |
|-------|-------------|
| **ADDR** | Memory address where fault occurred |
| **EXP** | Expected value (what was written) |
| **ACT** | Actual value (what was read back) |
| **DIFF** | XOR difference showing which bits failed |
| **%binary** | Visual representation of failed bits |
| **BAD CHIP** | Identified IC and data bit (for walking bit failures) |
| **FAIL ON PASS** | Pass number when fault occurred |
| **TEST** | Name of the test that detected the fault |

### Fault Messages

| Message | Meaning |
|---------|---------|
| `BAD CHIP: IC15 (D4)` | Walking bit test failed - specific chip fault identified? |
| `IC15 - INTERMITTENT?` | Pattern test failed on single bit - possible marginal chip? |
| `CHECK DATA BUS/TIMING` | Multiple bits failed - bus or timing issue? |

## How Chip Identification Works

Each 4164 DRAM chip stores one bit of each byte. When you write $AA to address $4000:

- IC12 stores bit 7 (1)
- IC13 stores bit 6 (0)
- IC14 stores bit 5 (1)
- IC15 stores bit 4 (0)
- IC16 stores bit 3 (1)
- IC17 stores bit 2 (0)
- IC18 stores bit 1 (1)
- IC19 stores bit 0 (0)

If IC12 fails and can't store a '1', reading back gives $2A instead of $AA:

```
Expected:  $AA = %10101010
Actual:    $2A = %00101010
                  ↑
XOR Diff:  $80 = %10000000
                  Bit 7 failed → IC12 is faulty
```

## Memory Coverage

Since this runs from ROM, it can test almost all RAM:

| Range | Size | Status |
|-------|------|--------|
| $0010-$00FF | 240 bytes | Zero page (tested) |
| $0200-$02FF | 256 bytes | Page 2 (tested) |
| $0400-$B3FF | 44.75 KB | Main RAM (tested) |
| **Total** | **~45.25 KB** | **Tested** |

Not tested (required by ROM or hardware):
- $0000-$000F - Program variables (16 bytes)
- $0100-$01FF - 6502 stack (256 bytes)
- $0300-$03FF - VIA I/O (256 bytes)
- $B400-$BFFF - Character set & screen (3 KB)
- $C000-$FFFF - ROM space

## Installation

### Using Pre-built ROM

1. Download `dram_fault_finder_rom_auto.bin` from the `bin/` folder
2. Burn to an EPROM (16KB) or add as a ROM to the diagnostic board


## Building from Source

See [BUILD.md](BUILD.md) for detailed build instructions.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Author

Kayto, January 2026.
