; hdmademo (a.k.a. "Butterfish" demo)
;
; Original author: Norman Yen / minus, 1993
; Originally intended for Tricks Assembler
;
; Modified by: Jeremy Chadwick / koitsu, 2019
; Intended for use with ca65 v2.18 or newer
; Includes several bugfixes and general improvements; see README.md

.feature c_comments
.setcpu "65816"
.smart +
.listbytes 64

; Equates and DEFINE macros taken from or inspired by libSFX:
; https://github.com/Optiroc/libSFX/blob/master/include/CPU_Def.i
;
; bgmap() addresses must be aligned to a 1K-word (2048-byte / $0800-byte) boundaries
; bgXXchr() addresses must be aligned to a 4K-word (8192-byte / $2000-byte) boundaries

.define ppuaddr(addr)             (addr / 2)
.define bgmode(mode, bg3_prio, bg1sz, bg2sz, bg3sz, bg4sz) ((mode & ~BG_MODE_MASK) | ((bg3_prio & 1) << BG_BG3_MAX_PRIO_SHIFT) | ((bg1sz & 1) << 4) | ((bg2sz & 1) << 5) | ((bg3sz & 1) << 6) | ((bg4sz & 1) << 7))
.define bgmap(addr, size)         ((((addr / 2) & $FC00) >> 8) | size)
.define bg12chr(bg1addr, bg2addr) (((bg2addr / 2) >> 8) | ((bg1addr / 2) >> 12))
.define bg34chr(bg3addr, bg4addr) (((bg4addr / 2) >> 8) | ((bg3addr / 2) >> 12))

SC_SIZE_32X32         = %00
SC_SIZE_64X32         = %01
SC_SIZE_32X64         = %10
SC_SIZE_64X64         = %11
BG_MODE_MASK          = $f8
BG_BG3_MAX_PRIO_SHIFT = 3
BG_MODE_1             = $01
BG_SIZE_8X8           = $0
BG_SIZE_16X16         = $1
BG3_PRIO_NORMAL       = $0
BG3_PRIO_HIGH         = $1        ; unused. if used, need to set priority bit in map tiles too

; PPU RAM map
; -------------------
bg1mapaddr  = $0000               ; $0000-0FFF: BG1 (fish) map, 2 horizontal screens
bg2mapaddr  = $1000               ; $1000-17FF: BG2 (reef) map, single screen
bg1chraddr  = $2000               ; $2000-xxxx: BG1 (fish) CHR data
bg2chraddr  = $6000               ; $6000-xxxx: BG2 (reef) CHR data

; General equates
; -------------------
bg1x_start  = 256                 ; BG1 (fish) X scroll starting position
bg1y_start  = 0                   ; BG1 (fish) Y scroll starting position

; Macros
; -------------------
.macro ZeroWRAM dstaddr, length
    ldx #(dstaddr & $FFFF)        ; WRAM address (A15-A0)
    stx $2181
    lda #((dstaddr >> 16) & $01)  ; WRAM bank (A16)
    sta $2183
    lda #%00001000                ; Single write, fixed source, CPU-->PPU
    sta $4300
    lda #$80                      ; Destination $2180 (WRAM data port)
    sta $4301
    ldx #.loword(ZeroByte)        ; Source offset
    stx $4302
    lda #.bankbyte(ZeroByte)      ; Source bank
    sta $4304
    ldx #(length & $FFFF)         ; Length ($0000 = 65536 bytes)
    stx $4305
    lda #$01                      ; Do DMA via channel 0
    sta $420B
.endmacro

.macro ZeroPPURAM dstaddr, length
    ldx #ppuaddr(dstaddr)         ; PPU RAM address
    stx $2116
    lda #%00001001                ; L,H write, fixed source, CPU-->PPU
    sta $4300
    lda #$18                      ; Destination $2118
    sta $4301
    ldx #.loword(ZeroByte)        ; Source offset
    stx $4302
    lda #.bankbyte(ZeroByte)      ; Source bank
    sta $4304
    ldx #(length & $FFFF)         ; Length ($0000 = 65536 bytes)
    stx $4305
    lda #$01                      ; Do DMA via channel 0
    sta $420B
.endmacro

.macro DMAPPURAM srcaddr, dstaddr, length
    ldx #ppuaddr(dstaddr)         ; PPU RAM address
    stx $2116
    lda #%00000001                ; L,H write, increment source, CPU-->PPU
    sta $4300
    lda #$18                      ; Destination $2118
    sta $4301
    ldx #.loword(srcaddr)         ; Source offset
    stx $4302
    lda #.bankbyte(srcaddr)       ; Source bank
    sta $4304
    ldx #length                   ; Length ($0000 = 65536 bytes)
    stx $4305
    lda #$01                      ; Do DMA via channel 0
    sta $420B
.endmacro

.macro DMACGRAM srcaddr, cgindex, length
    lda #cgindex                  ; CGRAM colour # / index
    sta $2121
    lda #%00000000                ; Single write, increment source, CPU-->PPU
    sta $4300
    lda #$22                      ; Destination $2122
    sta $4301
    ldx #.loword(srcaddr)         ; Source offset
    stx $4302
    lda #.bankbyte(srcaddr)       ; Source bank
    sta $4304
    ldx #length                   ; Length ($0000 = 65536 bytes)
    stx $4305
    lda #$01                      ; Do DMA via channel 0
    sta $420B
.endmacro

.segment "ZEROPAGE"
joypad1:      .res 2              ; Joypad 1 data
bg1x:         .res 2              ; BG1 X scroll position
bg1y:         .res 2              ; BG1 Y scroll position
hdmaStart:    .res 2              ; Index into sineHdmaTable, see evaluateHdmaValues
fishIndex:    .res 2              ; Index into sineFishTable, see mainLoop

.segment "RAM"
bg2x_data:    .res $02A1          ; RAM for HDMA table
bg2x_dataLen = *-bg2x_data

.segment "CODE"
.proc RESET
    sei                           ; Inhibit interrupts
    clc                           ; Native 65816 mode
    xce
    phk                           ; B = current code bank
    plb
    rep #$30                      ; A/X/Y=16
    lda #$0000                    ; D = $0000
    tcd
    ldx #$01ff                    ; S = $01FF
    txs

    sep #$30        ; make X, Y, A all 8-bits
    lda #$8f        ; forced blanking (screen off), full brightness
    sta $2100       ; brightness & screen enable register
    stz $2101       ; sprite register (size & address in VRAM)
    stz $2102       ; sprite registers (address of sprite memory [OAM])
    stz $2103       ; sprite registers (address of sprite memory [OAM])
    stz $2105       ; graphic mode register
    stz $2106       ; mosaic register
    stz $2107       ; plane 0 map VRAM location
    stz $2108       ; plane 1 map VRAM location
    stz $2109       ; plane 2 map VRAM location
    stz $210A       ; plane 3 map VRAM location
    stz $210B       ; plane 0 & 1 Tile data location
    stz $210C       ; plane 2 & 3 Tile data location
    stz $210D       ; plane 0 scroll x (first 8 bits)
    stz $210D       ; plane 0 scroll x (last 3 bits)
    stz $210E       ; plane 0 scroll y (first 8 bits)
    stz $210E       ; plane 0 scroll y (last 3 bits)
    stz $210F       ; plane 1 scroll x (first 8 bits)
    stz $210F       ; plane 1 scroll x (last 3 bits)
    stz $2110       ; plane 1 scroll y (first 8 bits)
    stz $2110       ; plane 1 scroll y (last 3 bits)
    stz $2111       ; plane 2 scroll x (first 8 bits)
    stz $2111       ; plane 2 scroll x (last 3 bits)
    stz $2112       ; plane 2 scroll y (first 8 bits)
    stz $2112       ; plane 2 scroll y (last 3 bits)
    stz $2113       ; plane 3 scroll x (first 8 bits)
    stz $2113       ; plane 3 scroll x (last 3 bits)
    stz $2114       ; plane 3 scroll y (first 8 bits)
    stz $2114       ; plane 3 scroll y (last 3 bits)
    lda #$80        ; increase VRAM address after writing to $2119
    sta $2115       ; VRAM address increment register
    stz $2116       ; VRAM address low
    stz $2117       ; VRAM address high
    stz $211A       ; initial mode 7 setting register
    stz $211B       ; mode 7 matrix parameter A register (low)
    lda #$01
    sta $211B       ; mode 7 matrix parameter A register (high)
    stz $211C       ; mode 7 matrix parameter B register (low)
    stz $211C       ; mode 7 matrix parameter B register (high)
    stz $211D       ; mode 7 matrix parameter C register (low)
    stz $211D       ; mode 7 matrix parameter C register (high)
    stz $211E       ; mode 7 matrix parameter D register (low)
    sta $211E       ; mode 7 matrix parameter D register (high) -- note sta, not stz!
    stz $211F       ; mode 7 center position X register (low)
    stz $211F       ; mode 7 center position X register (high)
    stz $2120       ; mode 7 center position Y register (low)
    stz $2120       ; mode 7 center position Y register (high)
    stz $2121       ; color number register ($00-$ff)
    stz $2123       ; bg1 & bg2 window mask setting register
    stz $2124       ; bg3 & bg4 window mask setting register
    stz $2125       ; obj & color window mask setting register
    stz $2126       ; window 1 left position register
    stz $2127       ; window 2 left position register
    stz $2128       ; window 3 left position register
    stz $2129       ; window 4 left position register
    stz $212A       ; bg1, bg2, bg3, bg4 window logic register
    stz $212B       ; obj, color window logic register (or, and, xor, xnor)
    stz $212C       ; main screen designation (planes, sprites enable)
    stz $212D       ; sub screen designation
    stz $212E       ; window mask for main screen
    stz $212F       ; window mask for sub screen
    lda #$30
    sta $2130       ; color addition & screen addition init setting
    stz $2131       ; add/sub sub designation for screen, sprite, color
    lda #$E0
    sta $2132       ; color data for addition/subtraction
    stz $2133       ; screen setting (interlace x,y/enable SFX data)
    stz $4200       ; enable v-blank, interrupt, joypad register
    lda #$FF
    sta $4201       ; programmable I/O port
    stz $4202       ; multiplicand A
    stz $4203       ; multiplier B
    stz $4204       ; multiplier C
    stz $4205       ; multiplicand C
    stz $4206       ; divisor B
    stz $4207       ; horizontal count timer
    stz $4208       ; horizontal count timer MSB
    stz $4209       ; vertical count timer
    stz $420A       ; vertical count timer MSB
    stz $420B       ; general DMA enable (bits 0-7)
    stz $420C       ; horizontal DMA (HDMA) enable (bits 0-7)
    stz $420D       ; access cycle designation (slowrom/normal 2.68MHz)

; We use these CPU register sizes throughout the rest of the entire demo
    rep #$30                      ; A/X/Y=16
    sep #$20                      ; A=8

; NOTE: WRAM $7E0000-7E1FFF is also $000000-001FFF, i.e. direct page and
; stack.  This is why we cannot turn this into a JSR/JSL-able subroutine
    ZeroWRAM $7E0000, 65536       ; Zero WRAM $7E0000-7EFFFF
    ZeroWRAM $7F0000, 65536       ; Zero WRAM $7F0000-7FFFFF

    ZeroPPURAM $0000, 65536       ; Zero PPU RAM ($0000-FFFF)

; Set up graphics mode, BG1/2 tile sizes
    lda #bgmode(BG_MODE_1, BG3_PRIO_NORMAL, BG_SIZE_8X8, BG_SIZE_8X8, $00, $00)
    sta $2105

; Set PPU RAM map addresses and screen sizes of BG1/BG2
    lda #bgmap(bg1mapaddr, SC_SIZE_64X32)
    sta $2107
    lda #bgmap(bg2mapaddr, SC_SIZE_32X32)
    sta $2108

; Set PPU RAM CHR address of BG1/BG2
    lda #bg12chr(bg1chraddr, bg2chraddr)
    sta $210B

; Transfer BG1 map data, palette, CHR to PPU RAM
; BG1 palette is CGRAM colours 0-15
    DMAPPURAM BG1Map, bg1mapaddr, BG1MapLen
    DMACGRAM  BG1Pal, 0, BG1PalLen
    DMAPPURAM BG1CHR, bg1chraddr, BG1CHRLen

; Transfer BG2 map data, palette, CHR to PPU RAM
; BG2 palette is CGRAM colours 16-31
    DMAPPURAM BG2Map, bg2mapaddr, BG2MapLen
    DMACGRAM  BG2Pal, 16, BG2PalLen
    DMAPPURAM BG2CHR, bg2chraddr, BG2CHRLen

; Initialise variables
    ldx #$0000
    stx hdmaStart
    stx fishIndex

; Set initial BG1 X/Y scroll position before turning screen on
    ldx #bg1x_start
    stx bg1x
    ldx #bg1y_start
    stx bg1y
    jsr SetBG1Scroll

; Initialise HDMA table in RAM for BG2 (reef)
    jsr evaluateHdmaValues

; Prep DMA channel 0 for HDMA
    lda #%00000010                ; HDMA write L,L, increment source, absolute
    sta $4300                     ; addressing, CPU-->PPU.  Data format: num-of-bytes, byte1, byte2
    lda #$0F                      ; Destination $210F (BG2 (reef) X scroll position)
    sta $4301
    ldx #.loword(bg2x_data)       ; Source address
    stx $4302
    lda #.bankbyte(bg2x_data)     ; Source bank
    sta $4304

    lda #%00000011                ; Enable BG1, BG2
    sta $212c

    cli                           ; Restore interrupts

    lda #%10000001                ; Enable NMI-on-VBlank and auto joypad read
    sta $4200

    lda #$01                      ; Do DMA via channel 0 (begin HDMA)
    sta $420C

; Forced blanking is currently on (done in SNES init), hence screen is off.
; We need to wait for 1 frame to be drawn/rendered -- for HDMA to set up
; BG2 X scroll -- before enabling the screen.  Otherwise, the BG2 reef is
; visually incorrect (only partially updated, semi-corrupt) for the very
; first frame.

    wai

    lda #$0F                      ; Enable screen, full brightness
    sta $2100

mainLoop:
    ldx bg1x                      ; Move BG1 (fish) X scroll right
    dex
    stx bg1x

    ldx fishIndex                 ; Adjust BG1 (fish) Y scroll via sine table
    lda sineFishTable,x
    sta bg1y
    lda sineFishTable+1,x
    sta bg1y+1
    inx
    inx
    cpx #sineFishTableLen
    bne :+
    ldx #0
:   stx fishIndex

    jsr evaluateHdmaValues        ; Update HDMA table in RAM for BG2 (reef)

    wai                           ; Wait for NMI/VBlank

    bra mainLoop
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Set the HDMA values for BG2 (reef)                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc evaluateHdmaValues
    ldx #0
    ldy hdmaStart
:   lda #1
    sta bg2x_data,x
    inx
    lda sineHdmaTable,y
    iny
    sta bg2x_data,x
    inx
    lda sineHdmaTable,y
    iny
    sta bg2x_data,x
    inx
    cpx #(bg2x_dataLen-1)
    bne :-
    lda #$00
    sta bg2x_data,x

    ldx hdmaStart
    inx
    inx
    cpx #(sineHdmaTableLen/2)
    bne :+
    ldx #0
:   stx hdmaStart
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Set BG1 X/Y scroll position (A must be 8-bit)                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc SetBG1Scroll
    lda bg1x
    sta $210D
    lda bg1x+1
    sta $210D

    lda bg1y
    sta $210E
    lda bg1y+1
    sta $210E

    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Vertical blank interrupt routine (uses A and X regs)                    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc NMI
    pha
    phx
    lda $4210                     ; Clear NMI latch

    jsr SetBG1Scroll              ; Update BG1 X/Y scroll position

:   lda $4212                     ; Wait until joypad ready (bit 0 = 0)
    and #$01
    bne :-

    ldx $4218                     ; Read joypad 1 ($4218 + $4219)
    stx joypad1

    plx
    pla
    rti
.endproc

; Unused vector point; this is purely for safety
.proc emptyvect
    rti
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sine table for BG1 (fish)                                               ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
sineFishTable: .incbin "fishsine.bin"
sineFishTableLen = *-sineFishTable

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sine table for HDMA on BG2 (reef)                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
sineHdmaTable: .incbin "sine.bin"
sineHdmaTableLen = *-sineHdmaTable

; Used for zeroing PPU RAM etc. via DMA
ZeroByte: .byte $00

; "New style" cartridge header ($FFB0-$FFDF)
.segment "CARTINFO"
    .byte "FF"                    ; $FFB0-FFB1: Maker code (2 bytes, ASCII BCD 0-F only)
    .byte "BXXX"                  ; $FFB2-FFB5: Game code (4 bytes ASCII, space-padded)
    .res  7, $00                  ; $FFB6-FFBC: Reserved (must be $00)
    .byte $00                     ; $FFBD:      Expansion RAM size ($00 = none)
    .byte $00                     ; $FFBE:      Special version ($00 = default)
    .byte $00                     ; $FFBF:      Cartridge sub-type ($00 = default)
    .byte "(C) 1993 Norman Yen  " ; $FFC0-FFD4: Title (21 bytes, space-padded)
    .byte $20                     ; $FFD5:      Mode ($20 = LoROM, slowrom/normal 2.68MHz)
    .byte $00                     ; $FFD6:      Type ($00 = ROM only)
    .byte $08                     ; $FFD7:      ROM size ($08 = 2mbit / 256KB)
    .byte $00                     ; $FFD8:      SRAM size ($00 = none)
    .byte $01                     ; $FFD9:      Destination code ($01 = North America)
    .byte $33                     ; $FFDA:      Reserved (must be $33)
    .byte $00                     ; $FFDB:      Mask ROM version #
    .word $FFFF                   ; $FFDC-FFDD: Checksum complement; filled in by ucon64
    .word $0000                   ; $FFDE-FFDF: Checksum; filled in by ucon64

.segment "VECTORS"
    .word emptyvect               ; $FFE4: native COP
    .word emptyvect               ; $FFE6: native BRK
    .word emptyvect               ; $FFE8: native ABORT
    .word NMI                     ; $FFEA: native NMI
    .word $0000                   ; $FFEC: n/a
    .word emptyvect               ; $FFEE: native IRQ
    .word $0000                   ; $FFF0: n/a
    .word $0000                   ; $FFF2: n/a
    .word emptyvect               ; $FFF4: emulation COP
    .word $0000                   ; $FFF6: n/a
    .word emptyvect               ; $FFF8: emulation ABORT
    .word NMI                     ; $FFFA: emulation NMI
    .word RESET                   ; $FFFC: emulation RESET
    .word emptyvect               ; $FFFE: emulation IRQ/BRK

; The .DAT files use a specific format:
;
; File offset $0000-07FF  = Map/layout data
; File offset $0800-081F  = Palette
; File offset $0820-<eof> = Character data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; BG1 (fish) data                                                         ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "BANK01"

BG1Map: .incbin "butrfish.dat", $0000, $0800
BG1MapLen = *-BG1Map

BG1Pal: .incbin "butrfish.dat", $0800, $20
BG1PalLen = *-BG1Pal

BG1CHR: .incbin "butrfish.dat", $0820
BG1CHRLen = *-BG1CHR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; BG2 (reef) data                                                         ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "BANK02"

BG2Map: .incbin "reef.dat", $0000, $0800
BG2MapLen = *-BG2Map

BG2Pal: .incbin "reef.dat", $0800, $20
BG2PalLen = *-BG2Pal

BG2CHR: .incbin "reef.dat", $0820
BG2CHRLen = *-BG2CHR
