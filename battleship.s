.segment "HEADER"
.byte $4E, $45, $53, $1A ; .byte "NES", $1A
.byte 2               ; 2x 16KB PRG code
.byte 1               ; 1x  8KB CHR data
.byte %00000000       ; mapper mmmm###M vertically mirrored, 0 - horizontally

.segment "VECTORS"
.addr nmi
.addr reset
.addr 0 ; IRQ

.segment "STARTUP" ; required by linker

.segment "ZEROPAGE"
state:        .byte $0
cursor_x:     .byte $0
cursor_y:     .byte $0
joypad1:      .byte $0
joypad2:      .byte $0
nmi_cnt:      .byte $0
render_off:   .byte $0
redraw:       .byte $0
nmi_skip:     .byte $0
skip_cnt:     .byte $0
nam_hi:       .byte $0
nam_lo:       .byte $0

; buffered tile updates
buf_pos_hi:   .byte $0
buf_pos_lo:   .byte $0

p1_grid:  .res 100, $00
p2_grid:  .res 100, $00


KEY_RIGHT = %00000001
KEY_LEFT  = %00000010
KEY_DOWN  = %00000100
KEY_UP    = %00001000
KEY_START = %00010000
KEY_SELECT= %00100000
KEY_B     = %01000000
KEY_A     = %10000000

; tiles
LOW_DASH   = $11
UP_DASH    = $01
LEFT_DASH  = $03
RIGHT_DASH = $02

; empty cell
E_UL = $06
E_UR = $07
E_LL = $16
E_LR = $17

F_UL = $08


.segment "CODE"
.proc reset
        sei		; disable IRQs
        cld		; disable decimal mode
        ldx #%01000000  ; 01000000 Interrupt inhibit flag.
        stx $4017	; disable APU frame IRQ
        ldx #$ff 	; Set up stack
        txs		;  .
        inx		; now X = 0
        stx $2000	; PPUCTRL. disable NMI, sprite size = 8x8
        stx $2001 	; PPUMASK. %00000000 disable all rendering
        stx $4010 	; disable DMC IRQs (delta modulation channel)
@vblankwait1:
        bit $2002 ; PPUSTATUS
        bpl @vblankwait1
@clear_memory:
        lda #$00
        sta $0000, x
        sta $0100, x
        sta $0200, x
        sta $0300, x
        sta $0400, x
        sta $0500, x
        sta $0600, x
        sta $0700, x
        inx
        bne @clear_memory
@vblankwait2:
        bit $2002 ; PPUSTATUS
        bpl @vblankwait2
        ; load palettes
        lda $2002 ; read from PPUSTATUS to reset PPU internal registers
        lda #$3f
        sta $2006 ; write upper byte of addr into PPURADDR
        lda #$00
        sta $2006 ; write lower byte of addr. PPUADDR = #$3F00
        ldx #$00
@loop:
        lda palettes, x
        sta $2007 ; PPUDATA
        inx
        cpx #$20 ; 32
        bne @loop

        ; load nametables
        jsr draw_title

        ; reset scroll
        lda #$00
        sta $2005
        sta $2005

        ; enable rendering
        lda #%10000000	; VPHBSINN NMI(V), PPU master/slave (P), sprite height (H), background tile select (B), sprite tile select (S), increment mode (I), nametable select / X and Y scroll bit 8 (NN)
        sta $2000
        lda #%00001000	; xxxSBxxx Enable Background rendering. No use of sprites in the game
        sta $2001 ; PPUMASK

@forever:
@state0:
        lda state
        bne @state1
        lda joypad1
        and #KEY_START
        beq @forever
        inc state

@state1:
        lda state
        cmp #$01
        bne @state2

        lda #$01
        sta render_off

        lda nmi_cnt
:
        cmp nmi_cnt
        beq :-

        jsr clear_nt0
        jsr draw_board
        jsr draw_p1_deploy

        lda nmi_cnt
:
        cmp nmi_cnt
        beq :-

        lda #$00
        sta render_off

        lda nmi_cnt
:
        cmp nmi_cnt
        beq :-

        inc state

@state2:
        lda state
        cmp #$02
        bne @state3

        jsr update_cursor
@state3:
        nop

@jmpforever:
        jmp @forever
.endproc

.proc update_cursor
        lda joypad1
        and #KEY_UP
        beq @exit_up
@wait_release_up:
        lda joypad1
        and #KEY_UP
        bne @wait_release_up
        dec cursor_x
        bpl @exit_up
        lda #00
        sta cursor_x
@exit_up:
        lda joypad1
        and #KEY_DOWN
        beq @skip_x
@wait_release_down:
        lda joypad1
        and #KEY_DOWN
        bne @wait_release_down
        lda cursor_x
        clc
        cmp #09
        bcs @skip_x
        inc cursor_x
@skip_x:

        lda joypad1
        and #KEY_LEFT
        beq @exit_left
@wait_release_left:
        lda joypad1
        and #KEY_LEFT
        bne @wait_release_left
        dec cursor_y
        bpl @exit_left
        lda #00
        sta cursor_y
@exit_left:

        lda joypad1
        and #KEY_RIGHT
        beq @skip_y
@wait_release_right:
        lda joypad1
        and #KEY_RIGHT
        bne @wait_release_right
        lda cursor_y
        clc
        cmp #09
        bcs @skip_y
        inc cursor_y
@skip_y:
        rts
.endproc

.proc nmi
        php
        pha
        txa
        pha
        tya
        pha

        inc nmi_cnt
        jsr read_joypad

        lda #%00001000 ; render background
        ldx render_off
        beq :+
        lda #%00000000 ; turn off render
:
        sta $2001

        bit $2002
        lda #$00 ; reset scroll
        sta $2005
        sta $2005

        pla
        tay
        pla
        tax
        pla
        plp

        rti
.endproc

.proc read_joypad
        lda #$01
        sta joypad1
        sta $4016 ; latch joypad1
        lsr ; A = 0
        sta $4016
:
        lda $4016
        lsr
        rol joypad1
        bcc :-
        lda #$01
        sta $4016
        sta joypad2
        lsr
        sta $4016
:
        lda $4017
        lsr
        rol joypad2
        bcc :-
        rts
.endproc

.proc draw_title
        lda $2002 ; read from PPUSTATUS to reset PPU internal registers
        lda #$21
        sta $2006
        lda #$4a
        sta $2006
        ldx #$00
:
        lda title, x
        beq @copyright
        sta $2007
        inx
        jmp :-
@copyright:
        lda #$22
        sta $2006
        lda #$01
        sta $2006
        ldx #$00
:
        lda copyright, x
        beq @github
        sta $2007
        inx
        jmp :-
@github:
        lda #$22
        sta $2006
        lda #$41
        sta $2006
        ldx #$00
        :
        lda github, x
        beq @reset_nametable
        sta $2007
        inx
        jmp :-
@reset_nametable:
        rts
.endproc

.proc clear_nt0
        bit $2002

        lda #$20
        sta $2006
        lda #$00
        sta $2006
        ldx #$00
:
        sta $2007
        inx
        bne :-

        lda #$21
        sta $2006
        lda #$00
        sta $2006
        ldx #$00
:
        sta $2007
        inx
        bne :-

        lda #$22
        sta $2006
        lda #$00
        sta $2006
        ldx #$00
:
        sta $2007
        inx
        bne :-

        lda #$23
        sta $2006
        lda #$00
        sta $2006
        ldx #$c0
:
        sta $2007
        dex
        bne :-

        rts
.endproc

.proc draw_p1_deploy
        ; 202A (x=10, y=1) - text
        lda #$20
        sta $2006
        lda #$2A
        sta $2006

        ldx #$00
        :
        lda p1_deploy, x
        beq :+
        sta $2007
        inx
        jmp :-
        :
        rts
.endproc

.proc draw_board
        ; 2066 (6,3) - grid upper left tile
        lda #$20
        sta $2006
        lda #$66
        sta $2006

        lda #LOW_DASH
        ldx #20
        :
        sta $2007
        dex
        bne :-

        ; 2086 (6,4)- upper half of cell tiles
        ldy #10

        lda #$20
        sta nam_hi
        lda #$86
        sta nam_lo

@fill_row:
        lda nam_hi
        sta $2006
        lda nam_lo
        sta $2006
        ldx #10
@fill_row_top:
        lda #E_UL
        sta $2007
        lda #E_UR
        sta $2007
        dex
        bne @fill_row_top

        clc
        lda nam_lo
        adc #$20
        sta nam_lo
        bcc :+
        inc nam_hi
:

        lda nam_hi
        sta $2006
        lda nam_lo
        sta $2006

        ldx #10
@fill_row_bottom:
        lda #E_LL
        sta $2007
        lda #E_LR
        sta $2007
        dex
        bne @fill_row_bottom

        dey
        beq @rows_done
        clc
        lda nam_lo
        adc #$20
        sta nam_lo
        bcc :+
        inc nam_hi
:
        jmp @fill_row

@rows_done:
        ; draw frame around cells
        lda #$23
        sta $2006
        lda #$06
        sta $2006
        ldx #20
:
        lda #UP_DASH
        sta $2007
        dex
        bne :-

        ; draw vertical frame
        ; 2065, 207a
        lda #%10000100	; increment mode (I)=1, inc by 32
        sta $2000

        lda #$20
        sta $2006
        lda #$85
        sta $2006

        ldx #20
:
        lda #RIGHT_DASH
        sta $2007
        dex
        bne :-

        lda #$20
        sta $2006
        lda #$9a
        sta $2006

        ldx #20
:
        lda #LEFT_DASH
        sta $2007
        dex
        bne :-

        lda #%10000000	; increment mode (I)=0, inc by 1
        sta $2000

        rts
.endproc


title:     .asciiz "BATTLESHIP"
copyright: .asciiz "(c) Sergey Lilo, 2025"
github:    .asciiz "github.com/lilo/battleship/"
p1_deploy: .asciiz "P1 deploy"
p2_deploy: .asciiz "P2 deploy"
p1_attack: .asciiz "P1 attack"
p2_attack: .asciiz "P2 attack"

palettes:
  ; Background Palette
;.byte $0f, $05, $00, $00 ; p0
.byte $0f, $20, $00, $00 ; p0
.byte $0f, $01, $00, $00 ; p1
.byte $0f, $05, $00, $00 ; p2
.byte $0f, $00, $00, $00 ; p3

; Sprite Palette
.byte $0f, $05, $00, $00 ; p0
.byte $0f, $01, $00, $00 ; p1
.byte $0f, $00, $00, $00 ; p2
.byte $0f, $00, $00, $00 ; p3

; Character memory
.segment "CHARS"
; .incbin "ascii.chr"
.incbin "battleship.chr"
