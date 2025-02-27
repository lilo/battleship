.segment "HEADER"
  .byte $4E, $45, $53, $1A ; .byte "NES", $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte %00000000       ; mapper mmmm###M 1-vertically mirrored, 0 - horizontaly

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
nametableLo: .byte $0
nametableHi: .byte $0
scrollX: .byte $0
scrollY: .byte $0
baseNametable: .byte $0

.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #%01000000  ; 01000000 Interrupt inhibit flag. If set, the frame interrupt flag is cleared, otherwise it is unaffected. 
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx $2000	; PPUCTRL. disable NMI, sprite size = 8x8
  stx $2001 	; PPUMASK. A value of $00 (%00000000) disables all rendering. disable rendering
  stx $4010 	; disable DMC IRQs (delta modulation channel)

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit $2002 ; PPUSTATUS
  bpl vblankwait1

clear_memory: ;
  lda #$00 ;
  sta $0000, x ;
  sta $0100, x ;
  sta $0200, x ;
  sta $0300, x ;
  sta $0400, x ;
  sta $0500, x ;
  sta $0600, x ;
  sta $0700, x ;
  inx ;
  bne clear_memory ;

;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit $2002 ; PPUSTATUS
  bpl vblankwait2

load_palettes:
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

load_nametable:
  jsr draw_title
  jsr draw_board

enable_rendering:
  lda #%10000000	; VPHBSINN NMI(V), PPU master/slave (P), sprite height (H), background tile select (B), sprite tile select (S), increment mode (I), nametable select / X and Y scroll bit 8 (NN)
  sta $2000
  lda #%00011000	; Enable Sprites and Background
  sta $2001 ; PPUMASK This register controls the rendering of sprites and backgrounds, as well as colour effects. 



forever:
  jmp forever

read_joypad:
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
        lda #$29
        sta $2006
        lda #$aa
        sta $2006

        lda #$45
        sta $2007
        sta $2007
        sta $2007
        sta $2007
        sta $2007

@reset_nametable:
        rts
.endproc

.proc nmi
        ldy scrollY
        lda baseNametable
        bne @endscroll
        inc scrollY
        cpy #240
        bne @scroll
        ldy #$00
        sty scrollY
        inc baseNametable
        inc baseNametable ; %00000010 (00 = $2000; 01 = $2400; 10 = $2800; 11 = $2C00)
@scroll:
        lda #$00
        sta $2006
        sta $2006

        ldx #$00
        stx $2005

        sty $2005

@endscroll:
        lda #%10000000
        ora baseNametable
        sta $2000

        lda #%00011000
        sta $2001

        rti
.endproc

title: .asciiz "BATTLESHIP"
copyright: .asciiz "(c) Sergey Lilo, 2025"
github: .asciiz "github.com/lilo/battleship/"


palettes:
  ; Background Palette
  .byte $09, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

  ; Sprite Palette
  .byte $0f, $05, $00, $00
  .byte $0f, $01, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

; Character memory
.segment "CHARS"
.incbin "ascii.chr"
