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
state:    .byte $0
cursor_x: .byte $0
cursor_y: .byte $0
p1_moves: .byte $0
p2_moves: .byte $0
p1_ships: .byte $0
p2_ships: .byte $0
p1_hits:  .byte $0
p2_hits:  .byte $0
joypad1:  .byte $0
joypad2:  .byte $0
nmi_cnt:  .byte $0
nt_lo:    .byte $0
nt_hi:    .byte $0
scrflag:  .byte $0
redraw:   .byte $0
scrollx:  .byte $0
scrolly:  .byte $0
base_nt:  .byte %00000000 ;00=$2000;01=$2400;10=$2800;11=$2C00
nmi_skip: .byte $0
skip_cnt: .byte $0

p1_grid:
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;

p2_grid:
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;
.byte $0, $0, $0, $0, $0, $0, $0, $0, $0, $0 ;


KEY_RIGHT = %00000001
KEY_LEFT  = %00000010
KEY_DOWN  = %00000100
KEY_UP    = %00001000
KEY_START = %00010000
KEY_SELECT= %00100000
KEY_B     = %01000000
KEY_A     = %10000000

D_SIDE = $11
U_SIDE = $01
R_SIDE = $02
L_SIDE = $03

E_UL = $16
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
        jsr draw_board

        ; reset scrollx, scrolly
        lda #$00
        sta $2006
        sta $2006

        ldx #$00
        stx $2005
        stx $2005

        ; enable rendering
        lda #%10000000	; VPHBSINN NMI(V), PPU master/slave (P), sprite height (H), background tile select (B), sprite tile select (S), increment mode (I), nametable select / X and Y scroll bit 8 (NN)
        sta $2000
        lda #%00011000	; xxxSBxxx Enable Sprites and Background
        sta $2001 ; PPUMASK

@forever:
@state0:
        lda state
        bne @state1
        lda joypad1
        and #KEY_START
        beq @forever
        inc state ; state = 1 - scroll

@state1:
        lda state
        cmp #$01
        bne @state2
        sta scrflag ; scrflag = 1
        inc scrolly
        ldy scrolly
        cpy #240
        bne @wait_nmi
        ldy #$00
        sty scrolly
        inc base_nt
        inc base_nt
        inc state ; state = 2 - p1 deploy

@state2:
        lda state
        cmp #$02
        bne @state3
        lda joypad1
        and #KEY_LEFT
        beq :+
        dec cursor_x
:
        lda joypad1
        and #KEY_RIGHT
        beq :+
        inc cursor_x
:
        lda joypad1
        and #KEY_UP
        beq :+
        dec cursor_y
:
        lda joypad1
        and #KEY_DOWN
        beq :+
        inc cursor_y
:
        lda joypad1
        and #KEY_A
        beq :+
        inc cursor_y
:
        lda joypad1
        and #KEY_B
        beq :+
        inc cursor_y
:
@wait_nmi2:        
        lda nmi_cnt
:
        cmp nmi_cnt
        beq :-
        lda #$00
        sta redraw

@state3:
@wait_nmi:        
        lda nmi_cnt
:
        cmp nmi_cnt
        beq :-

@jmpforever:
        jmp @forever
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

        lda nmi_skip
        beq :+
        inc skip_cnt
        jmp @skip
:

        lda scrflag
        beq @endscroll

@scroll:
        lda #$00
        sta $2006
        sta $2006

        ldx #$00
        stx $2005
        ldy scrolly
        sty $2005

@endscroll:

        lda redraw
        beq @endredraw
@endredraw:

        lda #%10000000
        ora base_nt
        sta $2000

        lda #%00011000
        sta $2001

@skip:
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

        ; jsr read_joypad ;
        ; lda #%00000010 !;\ right ;
        ; bit joypad1 ;
        ; bne :+ ;
        ; inc cursor_x ;
        ; : ;
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

.proc draw_board
        lda $2002 ; read from PPUSTATUS to reset PPU internal registers

        ; 282A - text
        lda #$28
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

        ; 2866 - grid 0,0
        lda #$28
        sta $2006
        lda #$66
        sta $2006

        lda #$11 ; underscore
        ldx #20
        :
        sta $2007
        dex
        bne :-

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
.byte $0f, $30, $00, $00 ; p0
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
