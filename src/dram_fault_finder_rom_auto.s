; ============================================
; ORIC DRAM FAULT FINDER - ROM
; ============================================
; Auto-running diagnostic tool that cycles through
; all memory tests continuously until fault detected.
;
; Author: Kayto
; Version: 1.0
; Date: January 2026
; License: MIT License
;
; CREDITS:
;   Character set data from Mike Brown's ORIC Diagnostic ROM:
;   https://oric.signal11.org.uk/html/diagrom.htm
;   
;   ORIC hardware documentation from Defence Force:
;   https://osdk.org/
;
;   Standard memory test algorithms (Walking Bit,
;   March patterns) are well-documented public domain.
;
; ROM INSTALLATION:
;   This code is designed to run from $C000.
;   It can be burned to a 16KB EPROM (27128) or
;   loaded into a ROM/RAM board at $C000.
;
; DRAM CHIP MAPPING (ORIC):
;   D7 = IC12    D3 = IC16
;   D6 = IC13    D2 = IC17
;   D5 = IC14    D1 = IC18
;   D4 = IC15    D0 = IC19
;
; MEMORY COVERAGE (ROM VERSION):
;   Tested:
;     $0010-$00FF - Zero page (240 bytes)
;     $0200-$02FF - Page 2 (256 bytes)
;     $0400-$B3FF - Main RAM (44.75 KB)
;     Total: ~45.25 KB tested
;
;   Not tested:
;     $0000-$000F - Our ZP variables (16 bytes)
;     $0100-$01FF - 6502 stack (256 bytes)
;     $0300-$03FF - VIA I/O (256 bytes)
;     $B400-$BFDF - Charsets + screen (3 KB)
;     $C000-$FFFF - ROM space
;
; Load address: $C000
; ============================================

; Hardware
SCREEN      = $BB80
MODE_ADDR   = $BFDF

; Screen layout
TITLE_ROW   = SCREEN           ; Row 0
STATUS_ROW  = SCREEN + 40      ; Row 1
TEST_ROW    = SCREEN + 80      ; Row 2  
ADDR_ROW    = SCREEN + 120     ; Row 3
DETAIL_ROW  = SCREEN + 160     ; Row 4
CHIP_ROW    = SCREEN + 200     ; Row 5
PASS_ROW    = SCREEN + 240     ; Row 6 - shows which pass failed

; Zero page - use absolute minimum
; We'll test $10-$FF, so only use $00-$0F for variables
ZP_LO       = $00
ZP_HI       = $01
ZP_PATTERN  = $02
ZP_TEMP     = $03
ZP_PASS_LO  = $04
ZP_PASS_HI  = $05
ZP_PAGE     = $06
ZP_EXPECTED = $07
ZP_ACTUAL   = $08
ZP_BITPOS   = $09
ZP_TESTID   = $0A              ; Current test ID for display
ZP_PTR_LO   = $0C              ; Pointer for test name (separate from ZP_LO/HI)
ZP_PTR_HI   = $0D

; Test IDs:
;   0 = Walking ZP
;   1 = Walking Page2  
;   2 = Walking Main
;   3 = AA55 ZP
;   4 = AA55 Page2
;   5 = AA55 Main
;   6 = FF00 ZP
;   7 = FF00 Page2
;   8 = FF00 Main
;   9 = Address Pattern

; ============================================
        .org $C000

CODE_START = *

; ============================================
; Interrupt Handlers (at start of ROM)
; ============================================

; NMI handler - just return
NMI_HANDLER:
        RTI

; IRQ handler - clear VIA interrupt flags
IRQ_HANDLER:
        PHA
        LDA $030D              ; Read VIA IFR
        STA $030D              ; Write back to clear
        PLA
        RTI

; ============================================
; VIA Initialization
; ============================================
VIA_INIT:
        LDA #$F7               ; All output except bit 3 (key sense)
        STA $0302              ; DDRB
        
        LDA #$00
        STA $0303              ; DDRA
        STA $030B              ; ACR
        STA $0300              ; IORB
        
        LDA #$CC               ; CB2=LOW, CA2=LOW
        STA $030C              ; PCR
        
        LDA #$7F               ; Disable all interrupts
        STA $030E              ; IER
        LDA #$7F               ; Clear all pending
        STA $030D              ; IFR
        RTS

; ============================================
; RESET entry point - AUTO START
; ============================================
START:
        SEI                    ; Disable interrupts
        CLD                    ; Clear decimal mode
        LDX #$FF
        TXS                    ; Initialize stack
        
        ; Initialize VIA
        JSR VIA_INIT
        
        ; Load character set from ROM to RAM ($B500)
        JSR LOAD_CHARSET
        
        ; TEXT mode
        LDA #$1A
        STA MODE_ADDR
        
        ; Clear screen
        JSR CLEAR_SCREEN
        
        ; Show title
        LDX #$00
@TITLE:
        LDA TITLE_TEXT,X
        BEQ @INIT
        STA TITLE_ROW,X
        INX
        BNE @TITLE

@INIT:
        ; Initialize pass counter
        LDA #$00
        STA ZP_PASS_LO
        STA ZP_PASS_HI

; ============================================
; Main test loop - cycles all tests each pass
; Loops forever until fault detected
; ============================================
MAIN_LOOP:
        ; Increment pass counter
        INC ZP_PASS_LO
        BNE @SHOW
        INC ZP_PASS_HI
@SHOW:
        JSR SHOW_PASS_COUNT
        
        ; Run all tests in sequence
        JSR TEST_WALKING_BIT_ALL
        JSR TEST_PATTERN_AA55_ALL
        JSR TEST_PATTERN_FF00_ALL
        JSR TEST_ADDRESS_PATTERN
        
        ; Loop forever
        JMP MAIN_LOOP

; ============================================
; TEST WRAPPERS - Test all memory regions
; ============================================
TEST_WALKING_BIT_ALL:
        ; Test zero page ($10-$FF)
        JSR TEST_WALKING_ZP
        ; Test page 2 ($0200-$02FF)
        JSR TEST_WALKING_PAGE2
        ; Test main RAM ($0400-$B3FF)
        JSR TEST_WALKING_BIT
        RTS

TEST_PATTERN_AA55_ALL:
        JSR TEST_PATTERN_AA55_ZP
        JSR TEST_PATTERN_AA55_PAGE2
        JSR TEST_PATTERN_AA55
        RTS

TEST_PATTERN_FF00_ALL:
        JSR TEST_PATTERN_FF00_ZP
        JSR TEST_PATTERN_FF00_PAGE2
        JSR TEST_PATTERN_FF00
        RTS

; ============================================
; ZERO PAGE TESTS ($10-$FF)
; ============================================
TEST_WALKING_ZP:
        LDA #$00
        STA ZP_TESTID          ; Test 0: Walking ZP
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        STA ZP_HI              ; Page 0
        
        LDA #$00
        STA ZP_BITPOS
        LDA #$01
        STA ZP_PATTERN
        
@BIT_LOOP:
        ; Write pattern to $10-$FF
        LDY #$10
        LDA ZP_PATTERN
@WRITE:
        STA $00,Y
        INY
        BNE @WRITE
        
        ; Verify
        LDY #$10
        LDA ZP_PATTERN
        STA ZP_EXPECTED
@VERIFY:
        LDA $00,Y
        CMP ZP_PATTERN
        BNE @ERROR
        INY
        BNE @VERIFY
        
        ; Next bit
        INC ZP_BITPOS
        ASL ZP_PATTERN
        BNE @BIT_LOOP
        
        ; Show progress
        LDA #$00
        STA ZP_PAGE
        JSR SHOW_PAGE
        RTS

@ERROR:
        STY ZP_LO
        STA ZP_ACTUAL
        JMP SHOW_CHIP_FAULT

TEST_PATTERN_AA55_ZP:
        LDA #$03
        STA ZP_TESTID          ; Test 3: AA55 ZP
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        STA ZP_HI
        
        ; Write $AA
        LDY #$10
        LDA #$AA
@WRITE_AA:
        STA $00,Y
        INY
        BNE @WRITE_AA
        
        ; Verify $AA
        LDY #$10
        LDA #$AA
        STA ZP_EXPECTED
@VERIFY_AA:
        LDA $00,Y
        CMP #$AA
        BNE @ERROR
        INY
        BNE @VERIFY_AA
        
        ; Write $55
        LDY #$10
        LDA #$55
@WRITE_55:
        STA $00,Y
        INY
        BNE @WRITE_55
        
        ; Verify $55
        LDY #$10
        LDA #$55
        STA ZP_EXPECTED
@VERIFY_55:
        LDA $00,Y
        CMP #$55
        BNE @ERROR
        INY
        BNE @VERIFY_55
        
        LDA #$00
        STA ZP_PAGE
        JSR SHOW_PAGE
        RTS

@ERROR:
        STY ZP_LO
        STA ZP_ACTUAL
        JMP SHOW_PATTERN_FAULT

TEST_PATTERN_FF00_ZP:
        LDA #$06
        STA ZP_TESTID          ; Test 6: FF00 ZP
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        STA ZP_HI
        
        ; Write $FF
        LDY #$10
        LDA #$FF
@WRITE_FF:
        STA $00,Y
        INY
        BNE @WRITE_FF
        
        ; Verify $FF
        LDY #$10
        LDA #$FF
        STA ZP_EXPECTED
@VERIFY_FF:
        LDA $00,Y
        CMP #$FF
        BNE @ERROR
        INY
        BNE @VERIFY_FF
        
        ; Write $00
        LDY #$10
        LDA #$00
@WRITE_00:
        STA $00,Y
        INY
        BNE @WRITE_00
        
        ; Verify $00
        LDY #$10
        LDA #$00
        STA ZP_EXPECTED
@VERIFY_00:
        LDA $00,Y
        CMP #$00
        BNE @ERROR
        INY
        BNE @VERIFY_00
        
        RTS

@ERROR:
        STY ZP_LO
        STA ZP_ACTUAL
        JMP SHOW_PATTERN_FAULT

; ============================================
; PAGE 2 TESTS ($0200-$02FF)
; ============================================
TEST_WALKING_PAGE2:
        LDA #$01
        STA ZP_TESTID          ; Test 1: Walking Page2
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        LDA #$02
        STA ZP_HI
        
        LDA #$00
        STA ZP_BITPOS
        LDA #$01
        STA ZP_PATTERN
        
@BIT_LOOP:
        ; Write pattern
        LDY #$00
        LDA ZP_PATTERN
@WRITE:
        STA (ZP_LO),Y
        INY
        BNE @WRITE
        
        ; Verify
        LDY #$00
        LDA ZP_PATTERN
        STA ZP_EXPECTED
@VERIFY:
        LDA (ZP_LO),Y
        CMP ZP_PATTERN
        BNE @ERROR
        INY
        BNE @VERIFY
        
        ; Next bit
        INC ZP_BITPOS
        ASL ZP_PATTERN
        BNE @BIT_LOOP
        
        LDA #$02
        STA ZP_PAGE
        JSR SHOW_PAGE
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_CHIP_FAULT

TEST_PATTERN_AA55_PAGE2:
        LDA #$04
        STA ZP_TESTID          ; Test 4: AA55 Page2
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        LDA #$02
        STA ZP_HI
        
        ; Write $AA
        LDY #$00
        LDA #$AA
@WRITE_AA:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_AA
        
        ; Verify $AA
        LDY #$00
        LDA #$AA
        STA ZP_EXPECTED
@VERIFY_AA:
        LDA (ZP_LO),Y
        CMP #$AA
        BNE @ERROR
        INY
        BNE @VERIFY_AA
        
        ; Write $55
        LDY #$00
        LDA #$55
@WRITE_55:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_55
        
        ; Verify $55
        LDY #$00
        LDA #$55
        STA ZP_EXPECTED
@VERIFY_55:
        LDA (ZP_LO),Y
        CMP #$55
        BNE @ERROR
        INY
        BNE @VERIFY_55
        
        LDA #$02
        STA ZP_PAGE
        JSR SHOW_PAGE
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_PATTERN_FAULT

TEST_PATTERN_FF00_PAGE2:
        LDA #$07
        STA ZP_TESTID          ; Test 7: FF00 Page2
        JSR SHOW_TEST_NAME
        LDA #$00
        STA ZP_LO
        LDA #$02
        STA ZP_HI
        
        ; Write $FF
        LDY #$00
        LDA #$FF
@WRITE_FF:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_FF
        
        ; Verify $FF
        LDY #$00
        LDA #$FF
        STA ZP_EXPECTED
@VERIFY_FF:
        LDA (ZP_LO),Y
        CMP #$FF
        BNE @ERROR
        INY
        BNE @VERIFY_FF
        
        ; Write $00
        LDY #$00
        LDA #$00
@WRITE_00:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_00
        
        ; Verify $00
        LDY #$00
        LDA #$00
        STA ZP_EXPECTED
@VERIFY_00:
        LDA (ZP_LO),Y
        CMP #$00
        BNE @ERROR
        INY
        BNE @VERIFY_00
        
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_PATTERN_FAULT

; ============================================
; MAIN RAM TESTS ($0400-$B3FF)
; ============================================
TEST_PATTERN_AA55:
        LDA #$05
        STA ZP_TESTID          ; Test 5: AA55 Main
        JSR SHOW_TEST_NAME
        LDA #$04
        STA ZP_PAGE
        
@PAGE_LOOP:
        LDA #$00
        STA ZP_LO
        LDA ZP_PAGE
        STA ZP_HI
        
        ; Write $AA
        LDY #$00
        LDA #$AA
@WRITE_AA:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_AA
        
        ; Verify $AA
        LDY #$00
        LDA #$AA
        STA ZP_EXPECTED
@VERIFY_AA:
        LDA (ZP_LO),Y
        CMP #$AA
        BNE @ERROR
        INY
        BNE @VERIFY_AA
        
        ; Write $55
        LDY #$00
        LDA #$55
@WRITE_55:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_55
        
        ; Verify $55
        LDY #$00
        LDA #$55
        STA ZP_EXPECTED
@VERIFY_55:
        LDA (ZP_LO),Y
        CMP #$55
        BNE @ERROR
        INY
        BNE @VERIFY_55
        
        ; Update display
        JSR SHOW_PAGE
        
        ; Next page
        INC ZP_PAGE
        LDA ZP_PAGE
        CMP #$B4               ; Stop before charsets
        BCC @PAGE_LOOP
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_PATTERN_FAULT

TEST_PATTERN_FF00:
        LDA #$08
        STA ZP_TESTID          ; Test 8: FF00 Main
        JSR SHOW_TEST_NAME
        LDA #$04
        STA ZP_PAGE
        
@PAGE_LOOP:
        LDA #$00
        STA ZP_LO
        LDA ZP_PAGE
        STA ZP_HI
        
        ; Write $FF
        LDY #$00
        LDA #$FF
@WRITE_FF:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_FF
        
        ; Verify $FF
        LDY #$00
        LDA #$FF
        STA ZP_EXPECTED
@VERIFY_FF:
        LDA (ZP_LO),Y
        CMP #$FF
        BNE @ERROR
        INY
        BNE @VERIFY_FF
        
        ; Write $00
        LDY #$00
        LDA #$00
@WRITE_00:
        STA (ZP_LO),Y
        INY
        BNE @WRITE_00
        
        ; Verify $00
        LDY #$00
        LDA #$00
        STA ZP_EXPECTED
@VERIFY_00:
        LDA (ZP_LO),Y
        CMP #$00
        BNE @ERROR
        INY
        BNE @VERIFY_00
        
        ; Update display
        JSR SHOW_PAGE
        
        ; Next page
        INC ZP_PAGE
        LDA ZP_PAGE
        CMP #$B4
        BCC @PAGE_LOOP
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_PATTERN_FAULT

TEST_WALKING_BIT:
        LDA #$02
        STA ZP_TESTID          ; Test 2: Walking Main
        JSR SHOW_TEST_NAME
        LDA #$04
        STA ZP_PAGE
        
@PAGE_LOOP:
        LDA #$00
        STA ZP_LO
        LDA ZP_PAGE
        STA ZP_HI
        
        ; Test each bit position (0-7)
        LDA #$00
        STA ZP_BITPOS
        LDA #$01
        STA ZP_PATTERN
        
@BIT_LOOP:
        ; Write walking bit pattern
        LDY #$00
        LDA ZP_PATTERN
@WRITE:
        STA (ZP_LO),Y
        INY
        BNE @WRITE
        
        ; Verify
        LDY #$00
        LDA ZP_PATTERN
        STA ZP_EXPECTED
@VERIFY:
        LDA (ZP_LO),Y
        CMP ZP_PATTERN
        BNE @ERROR
        INY
        BNE @VERIFY
        
        ; Next bit
        INC ZP_BITPOS
        ASL ZP_PATTERN
        BNE @BIT_LOOP
        
        ; Update display
        JSR SHOW_PAGE
        
        ; Next page
        INC ZP_PAGE
        LDA ZP_PAGE
        CMP #$B4
        BCC @PAGE_LOOP
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_CHIP_FAULT

TEST_ADDRESS_PATTERN:
        LDA #$09
        STA ZP_TESTID          ; Test 9: Address Pattern
        JSR SHOW_TEST_NAME
        LDA #$04
        STA ZP_PAGE
        
@PAGE_LOOP:
        LDA #$00
        STA ZP_LO
        LDA ZP_PAGE
        STA ZP_HI
        
        ; Write address-based pattern
        LDY #$00
@WRITE:
        TYA
        EOR ZP_PAGE
        STA (ZP_LO),Y
        INY
        BNE @WRITE
        
        ; Verify
        LDY #$00
@VERIFY:
        TYA
        EOR ZP_PAGE
        STA ZP_EXPECTED
        LDA (ZP_LO),Y
        CMP ZP_EXPECTED
        BNE @ERROR
        INY
        BNE @VERIFY
        
        ; Update display
        JSR SHOW_PAGE
        
        ; Next page
        INC ZP_PAGE
        LDA ZP_PAGE
        CMP #$B4
        BCC @PAGE_LOOP
        RTS

@ERROR:
        STA ZP_ACTUAL
        STY ZP_LO
        JMP SHOW_PATTERN_FAULT

; ============================================
; SHOW_CHIP_FAULT - Walking bit failure
; ============================================
SHOW_CHIP_FAULT:
        JSR SHOW_FAULT_HEADER
        
        ; Row 5: Show "BAD CHIP: ICxx (Dn)"
        LDA #'B'
        STA CHIP_ROW
        LDA #'A'
        STA CHIP_ROW+1
        LDA #'D'
        STA CHIP_ROW+2
        LDA #' '
        STA CHIP_ROW+3
        LDA #'C'
        STA CHIP_ROW+4
        LDA #'H'
        STA CHIP_ROW+5
        LDA #'I'
        STA CHIP_ROW+6
        LDA #'P'
        STA CHIP_ROW+7
        LDA #':'
        STA CHIP_ROW+8
        LDA #' '
        STA CHIP_ROW+9
        LDA #'I'
        STA CHIP_ROW+10
        LDA #'C'
        STA CHIP_ROW+11
        LDA #'1'
        STA CHIP_ROW+12
        
        ; IC number = 19 - bit_position
        LDA #$09
        SEC
        SBC ZP_BITPOS
        CLC
        ADC #'0'
        STA CHIP_ROW+13
        
        ; Show " (Dn)"
        LDA #' '
        STA CHIP_ROW+14
        LDA #'('
        STA CHIP_ROW+15
        LDA #'D'
        STA CHIP_ROW+16
        LDA ZP_BITPOS
        CLC
        ADC #'0'
        STA CHIP_ROW+17
        LDA #')'
        STA CHIP_ROW+18
        
@HALT:
        JMP @HALT

; ============================================
; SHOW_PATTERN_FAULT - Pattern test failure
; ============================================
SHOW_PATTERN_FAULT:
        JSR SHOW_FAULT_HEADER
        
        ; Count bad bits
        LDA ZP_TEMP
        STA ZP_PATTERN
        LDX #$00
        LDY #$00
        STY ZP_BITPOS
@COUNT:
        LSR ZP_PATTERN
        BCC @NEXT
        INX
        CPX #$01
        BNE @NEXT
        STY ZP_BITPOS
@NEXT:
        INY
        CPY #$08
        BCC @COUNT
        
        CPX #$01
        BEQ @SINGLE
        
        ; Multiple bits - show bus warning
        LDX #$00
@MULTI:
        LDA MULTI_TEXT,X
        BEQ @HALT
        STA CHIP_ROW,X
        INX
        BNE @MULTI
        
@SINGLE:
        ; Single bit - intermittent
        LDA #'I'
        STA CHIP_ROW
        LDA #'C'
        STA CHIP_ROW+1
        LDA #'1'
        STA CHIP_ROW+2
        LDA #$09
        SEC
        SBC ZP_BITPOS
        CLC
        ADC #'0'
        STA CHIP_ROW+3
        LDA #' '
        STA CHIP_ROW+4
        LDA #'-'
        STA CHIP_ROW+5
        LDA #' '
        STA CHIP_ROW+6
        LDA #'I'
        STA CHIP_ROW+7
        LDA #'N'
        STA CHIP_ROW+8
        LDA #'T'
        STA CHIP_ROW+9
        LDA #'E'
        STA CHIP_ROW+10
        LDA #'R'
        STA CHIP_ROW+11
        LDA #'M'
        STA CHIP_ROW+12
        LDA #'I'
        STA CHIP_ROW+13
        LDA #'T'
        STA CHIP_ROW+14
        LDA #'T'
        STA CHIP_ROW+15
        LDA #'E'
        STA CHIP_ROW+16
        LDA #'N'
        STA CHIP_ROW+17
        LDA #'T'
        STA CHIP_ROW+18
        LDA #'?'
        STA CHIP_ROW+19
        
@HALT:
        JMP @HALT

; ============================================
; SHOW_FAULT_HEADER - Common fault display
; ============================================
SHOW_FAULT_HEADER:
        ; Clear status rows
        LDX #$00
        LDA #' '
@CLEAR:
        STA STATUS_ROW,X
        STA TEST_ROW,X
        STA ADDR_ROW,X
        STA DETAIL_ROW,X
        STA CHIP_ROW,X
        STA PASS_ROW,X
        INX
        CPX #$28
        BCC @CLEAR
        
        ; Row 1: "FAULT DETECTED!"
        LDX #$00
@FAULT_MSG:
        LDA FAULT_TEXT,X
        BEQ @ROW2
        STA STATUS_ROW,X
        INX
        BNE @FAULT_MSG
        
@ROW2:
        ; Row 2: "ADDR: $xxxx"
        LDA #'A'
        STA TEST_ROW
        LDA #'D'
        STA TEST_ROW+1
        STA TEST_ROW+2
        LDA #'R'
        STA TEST_ROW+3
        LDA #':'
        STA TEST_ROW+4
        LDA #' '
        STA TEST_ROW+5
        LDA #'$'
        STA TEST_ROW+6
        
        ; Address high byte
        LDA ZP_HI
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+7
        LDA ZP_HI
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+8
        
        ; Address low byte
        LDA ZP_LO
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+9
        LDA ZP_LO
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+10
        
@ROW3:
        ; Row 3: "EXP: $xx  ACT: $xx"
        LDA #'E'
        STA ADDR_ROW
        LDA #'X'
        STA ADDR_ROW+1
        LDA #'P'
        STA ADDR_ROW+2
        LDA #':'
        STA ADDR_ROW+3
        LDA #' '
        STA ADDR_ROW+4
        LDA #'$'
        STA ADDR_ROW+5
        
        LDA ZP_EXPECTED
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+6
        LDA ZP_EXPECTED
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+7
        
        LDA #' '
        STA ADDR_ROW+8
        STA ADDR_ROW+9
        LDA #'A'
        STA ADDR_ROW+10
        LDA #'C'
        STA ADDR_ROW+11
        LDA #'T'
        STA ADDR_ROW+12
        LDA #':'
        STA ADDR_ROW+13
        LDA #' '
        STA ADDR_ROW+14
        LDA #'$'
        STA ADDR_ROW+15
        
        LDA ZP_ACTUAL
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+16
        LDA ZP_ACTUAL
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+17
        
@ROW4:
        ; Row 4: "DIFF: $xx  %xxxxxxxx"
        LDA #'D'
        STA DETAIL_ROW
        LDA #'I'
        STA DETAIL_ROW+1
        LDA #'F'
        STA DETAIL_ROW+2
        STA DETAIL_ROW+3
        LDA #':'
        STA DETAIL_ROW+4
        LDA #' '
        STA DETAIL_ROW+5
        LDA #'$'
        STA DETAIL_ROW+6
        
        ; Calculate XOR difference
        LDA ZP_EXPECTED
        EOR ZP_ACTUAL
        STA ZP_TEMP
        
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA DETAIL_ROW+7
        LDA ZP_TEMP
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA DETAIL_ROW+8
        
        LDA #' '
        STA DETAIL_ROW+9
        STA DETAIL_ROW+10
        LDA #'%'
        STA DETAIL_ROW+11
        
        ; Binary bits
        LDA ZP_TEMP
        LDX #$00
@BIN_LOOP:
        ASL A
        PHA
        BCS @BIT_ONE
        LDA #'0'
        JMP @STORE_BIT
@BIT_ONE:
        LDA #'1'
@STORE_BIT:
        STA DETAIL_ROW+12,X
        PLA
        INX
        CPX #$08
        BCC @BIN_LOOP
        
        ; Row 6: "FAIL ON PASS: xxxx"
        LDA #'F'
        STA PASS_ROW
        LDA #'A'
        STA PASS_ROW+1
        LDA #'I'
        STA PASS_ROW+2
        LDA #'L'
        STA PASS_ROW+3
        LDA #' '
        STA PASS_ROW+4
        LDA #'O'
        STA PASS_ROW+5
        LDA #'N'
        STA PASS_ROW+6
        LDA #' '
        STA PASS_ROW+7
        LDA #'P'
        STA PASS_ROW+8
        LDA #'A'
        STA PASS_ROW+9
        LDA #'S'
        STA PASS_ROW+10
        STA PASS_ROW+11
        LDA #':'
        STA PASS_ROW+12
        LDA #' '
        STA PASS_ROW+13
        
        ; Pass count
        LDA ZP_PASS_HI
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA PASS_ROW+14
        LDA ZP_PASS_HI
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA PASS_ROW+15
        
        LDA ZP_PASS_LO
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA PASS_ROW+16
        LDA ZP_PASS_LO
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA PASS_ROW+17
        
        ; Add test name on row 7 (SCREEN + 280)
        JSR SHOW_FAIL_TEST_NAME
        
        RTS

; ============================================
; SHOW_FAIL_TEST_NAME - Show test name on failure
; ============================================
SHOW_FAIL_TEST_NAME:
        ; Show "TEST: " prefix
        LDA #'T'
        STA SCREEN+280
        LDA #'E'
        STA SCREEN+281
        LDA #'S'
        STA SCREEN+282
        LDA #'T'
        STA SCREEN+283
        LDA #':'
        STA SCREEN+284
        LDA #' '
        STA SCREEN+285
        
        ; Get pointer to test name (use separate ZP locations)
        LDA ZP_TESTID
        ASL A
        TAX
        LDA TEST_NAME_TBL,X
        STA ZP_PTR_LO
        LDA TEST_NAME_TBL+1,X
        STA ZP_PTR_HI
        
        ; Copy test name
        LDY #$00
@LOOP:
        LDA (ZP_PTR_LO),Y
        BEQ @DONE
        STA SCREEN+286,Y
        INY
        CPY #$22               ; Max chars
        BCC @LOOP
@DONE:
        RTS

; ============================================
; Display routines
; ============================================
CLEAR_SCREEN:
        LDA #<SCREEN
        STA ZP_LO
        LDA #>SCREEN
        STA ZP_HI
        LDA #$20
        LDY #$00
        LDX #$05
@LOOP:
        STA (ZP_LO),Y
        INY
        BNE @LOOP
        INC ZP_HI
        DEX
        BNE @LOOP
        RTS

SHOW_PASS_COUNT:
        LDA #'P'
        STA TEST_ROW
        LDA #'A'
        STA TEST_ROW+1
        LDA #'S'
        STA TEST_ROW+2
        STA TEST_ROW+3
        LDA #':'
        STA TEST_ROW+4
        LDA #' '
        STA TEST_ROW+5
        
        LDA ZP_PASS_HI
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+6
        LDA ZP_PASS_HI
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+7
        
        LDA ZP_PASS_LO
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+8
        LDA ZP_PASS_LO
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA TEST_ROW+9
        RTS

SHOW_PAGE:
        LDA #'P'
        STA ADDR_ROW
        LDA #'A'
        STA ADDR_ROW+1
        LDA #'G'
        STA ADDR_ROW+2
        LDA #'E'
        STA ADDR_ROW+3
        LDA #':'
        STA ADDR_ROW+4
        LDA #' '
        STA ADDR_ROW+5
        LDA #'$'
        STA ADDR_ROW+6
        
        LDA ZP_PAGE
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+7
        LDA ZP_PAGE
        AND #$0F
        TAX
        LDA HEX_CHARS,X
        STA ADDR_ROW+8
        RTS

; ============================================
; SHOW_TEST_NAME - Display current test name
; Uses ZP_TESTID to select test name string
; ============================================
SHOW_TEST_NAME:
        ; Get pointer to test name string (use separate ZP locations)
        LDA ZP_TESTID
        ASL A                  ; Multiply by 2 for table index
        TAX
        LDA TEST_NAME_TBL,X
        STA ZP_PTR_LO
        LDA TEST_NAME_TBL+1,X
        STA ZP_PTR_HI
        
        ; Display on DETAIL_ROW
        LDY #$00
@LOOP:
        LDA (ZP_PTR_LO),Y
        BEQ @DONE
        STA DETAIL_ROW,Y
        INY
        CPY #$28               ; Max 40 chars
        BCC @LOOP
@DONE:
        ; Pad rest with spaces
@PAD:
        CPY #$28
        BCS @EXIT
        LDA #' '
        STA DETAIL_ROW,Y
        INY
        JMP @PAD
@EXIT:
        RTS

; ============================================
; Data
; ============================================
TITLE_TEXT:
        .byte "ORIC DRAM FAULT FINDER", 0

FAULT_TEXT:
        .byte "*** FAULT DETECTED! ***", 0

MULTI_TEXT:
        .byte "CHECK DATA BUS/TIMING", 0

HEX_CHARS:
        .byte "0123456789ABCDEF"

; Test name strings
TEST_WALK:
        .byte "WALKING BIT", 0
TEST_AA55:
        .byte "AA55 PATTERN", 0
TEST_FF00:
        .byte "FF00 PATTERN", 0
TEST_ADDR:
        .byte "ADDRESS PATTERN", 0

; Table of test name pointers
TEST_NAME_TBL:
        .word TEST_WALK        ; 0 - Walking ZP
        .word TEST_WALK        ; 1 - Walking Page2
        .word TEST_WALK        ; 2 - Walking Main
        .word TEST_AA55        ; 3 - AA55 ZP
        .word TEST_AA55        ; 4 - AA55 Page2
        .word TEST_AA55        ; 5 - AA55 Main
        .word TEST_FF00        ; 6 - FF00 ZP
        .word TEST_FF00        ; 7 - FF00 Page2
        .word TEST_FF00        ; 8 - FF00 Main
        .word TEST_ADDR        ; 9 - Address Pattern

; ============================================
; Character set data (768 bytes from ORIC ROM)
; ============================================
CHARSET_DATA:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$08,$08,$08,$00,$08,$00
        .byte $14,$14,$14,$00,$00,$00,$00,$00,$14,$14,$3E,$14,$3E,$14,$14,$00
        .byte $08,$1E,$28,$1C,$0A,$3C,$08,$00,$30,$32,$04,$08,$10,$26,$06,$00
        .byte $10,$28,$28,$10,$2A,$24,$1A,$00,$08,$08,$08,$00,$00,$00,$00,$00
        .byte $08,$10,$20,$20,$20,$10,$08,$00,$08,$04,$02,$02,$02,$04,$08,$00
        .byte $08,$2A,$1C,$08,$1C,$2A,$08,$00,$00,$08,$08,$3E,$08,$08,$00,$00
        .byte $00,$00,$00,$00,$00,$08,$08,$10,$00,$00,$00,$3E,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$04,$00,$00,$00,$02,$04,$08,$10,$20,$00,$00
        .byte $1C,$22,$26,$2A,$32,$22,$1C,$00,$08,$18,$08,$08,$08,$08,$1C,$00
        .byte $1C,$22,$02,$04,$08,$10,$3E,$00,$3E,$02,$04,$0C,$02,$22,$1C,$00
        .byte $04,$0C,$14,$24,$3E,$04,$04,$00,$3E,$20,$3C,$02,$02,$22,$1C,$00
        .byte $0C,$10,$20,$3C,$22,$22,$1C,$00,$3E,$02,$04,$08,$10,$10,$10,$00
        .byte $1C,$22,$22,$1C,$22,$22,$1C,$00,$1C,$22,$22,$1E,$02,$04,$18,$00
        .byte $00,$00,$08,$00,$00,$08,$00,$00,$00,$00,$08,$00,$00,$08,$08,$10
        .byte $04,$08,$10,$20,$10,$08,$04,$00,$00,$00,$3E,$00,$3E,$00,$00,$00
        .byte $10,$08,$04,$02,$04,$08,$10,$00,$1C,$22,$04,$08,$08,$00,$08,$00
        .byte $1C,$22,$2A,$2E,$2C,$20,$1E,$00,$08,$14,$22,$22,$3E,$22,$22,$00
        .byte $3C,$22,$22,$3C,$22,$22,$3C,$00,$1C,$22,$20,$20,$20,$22,$1C,$00
        .byte $3C,$22,$22,$22,$22,$22,$3C,$00,$3E,$20,$20,$3C,$20,$20,$3E,$00
        .byte $3E,$20,$20,$3C,$20,$20,$20,$00,$1E,$20,$20,$20,$26,$22,$1E,$00
        .byte $22,$22,$22,$3E,$22,$22,$22,$00,$1C,$08,$08,$08,$08,$08,$1C,$00
        .byte $02,$02,$02,$02,$02,$22,$1C,$00,$22,$24,$28,$30,$28,$24,$22,$00
        .byte $20,$20,$20,$20,$20,$20,$3E,$00,$22,$36,$2A,$2A,$22,$22,$22,$00
        .byte $22,$22,$32,$2A,$26,$22,$22,$00,$1C,$22,$22,$22,$22,$22,$1C,$00
        .byte $3C,$22,$22,$3C,$20,$20,$20,$00,$1C,$22,$22,$22,$2A,$24,$1A,$00
        .byte $3C,$22,$22,$3C,$28,$24,$22,$00,$1C,$22,$20,$1C,$02,$22,$1C,$00
        .byte $3E,$08,$08,$08,$08,$08,$08,$00,$22,$22,$22,$22,$22,$22,$1C,$00
        .byte $22,$22,$22,$22,$22,$14,$08,$00,$22,$22,$22,$2A,$2A,$36,$22,$00
        .byte $22,$22,$14,$08,$14,$22,$22,$00,$22,$22,$14,$08,$08,$08,$08,$00
        .byte $3E,$02,$04,$08,$10,$20,$3E,$00,$1E,$10,$10,$10,$10,$10,$1E,$00
        .byte $00,$20,$10,$08,$04,$02,$00,$00,$3C,$04,$04,$04,$04,$04,$3C,$00
        .byte $08,$14,$2A,$08,$08,$08,$08,$00,$0E,$10,$10,$10,$3C,$10,$3E,$00
        .byte $0C,$12,$2D,$29,$29,$2D,$12,$0C,$00,$00,$1C,$02,$1E,$22,$1E,$00
        .byte $20,$20,$3C,$22,$22,$22,$3C,$00,$00,$00,$1E,$20,$20,$20,$1E,$00
        .byte $02,$02,$1E,$22,$22,$22,$1E,$00,$00,$00,$1C,$22,$3E,$20,$1E,$00
        .byte $0C,$12,$10,$3C,$10,$10,$10,$00,$00,$00,$1C,$22,$22,$1E,$02,$1C
        .byte $20,$20,$3C,$22,$22,$22,$22,$00,$08,$00,$18,$08,$08,$08,$1C,$00
        .byte $04,$00,$0C,$04,$04,$04,$24,$18,$20,$20,$22,$24,$38,$24,$22,$00
        .byte $18,$08,$08,$08,$08,$08,$1C,$00,$00,$00,$36,$2A,$2A,$2A,$22,$00
        .byte $00,$00,$3C,$22,$22,$22,$22,$00,$00,$00,$1C,$22,$22,$22,$1C,$00
        .byte $00,$00,$3C,$22,$22,$3C,$20,$20,$00,$00,$1E,$22,$22,$1E,$02,$02
        .byte $00,$00,$2E,$30,$20,$20,$20,$00,$00,$00,$1E,$20,$1C,$02,$3C,$00
        .byte $10,$10,$3C,$10,$10,$12,$0C,$00,$00,$00,$22,$22,$22,$26,$1A,$00
        .byte $00,$00,$22,$22,$22,$14,$08,$00,$00,$00,$22,$22,$2A,$2A,$36,$00
        .byte $00,$00,$22,$14,$08,$14,$22,$00,$00,$00,$22,$22,$22,$1E,$02,$1C
        .byte $00,$00,$3E,$04,$08,$10,$3E,$00,$0E,$18,$18,$30,$18,$18,$0E,$00
        .byte $08,$08,$08,$08,$08,$08,$08,$08,$38,$0C,$0C,$06,$0C,$0C,$38,$00
        .byte $2A,$15,$2A,$15,$2A,$15,$2A,$15,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F

; ============================================
; Copy charset from ROM to RAM at $B500
; ============================================
LOAD_CHARSET:
        LDX #$00
@LOOP1:
        LDA CHARSET_DATA,X
        STA $B500,X
        LDA CHARSET_DATA+$100,X
        STA $B600,X
        LDA CHARSET_DATA+$200,X
        STA $B700,X
        INX
        BNE @LOOP1
        RTS

; ============================================
; End of code
; ============================================
CODE_END = *

; ============================================
; 6502 Vectors at $FFFA-$FFFF
; ============================================
        .res $FFFA - *, $FF    ; Pad with $FF to vector location

        .word NMI_HANDLER      ; $FFFA - NMI vector
        .word START            ; $FFFC - RESET vector
        .word IRQ_HANDLER      ; $FFFE - IRQ/BRK vector

        .out .sprintf("ROM total size: %d bytes (16KB)", $10000 - $C000)
