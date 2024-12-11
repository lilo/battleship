.segment "HEADER"
  ; .byte "NES", $1A      ; iNES header identifier
  .byte $4E, $45, $53, $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .addr nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .addr reset
  ;; External interrupt IRQ (unused)
  .addr 0

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

.segment "ZEROPAGE"
state:    .byte $0
cursor_x:   .byte $0
cursor_y:   .byte $0
p1_moves: .byte $0
p2_moves: .byte $0
p1_map:   .byte $0
p2_map:   .byte $0
joypad1:  .byte $0
joypad2:  .byte $0

; Main code segment for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40      ; 01000000 Interrupt inhibit flag. If set, the frame interrupt flag is cleared, otherwise it is unaffected. 
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

main:
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

enable_rendering:
  lda #%10000000	; Enable NMI
  sta $2000
  lda #%00010000	; Enable Sprites
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

nmi:
  jsr read_joypad
  lda #%00000010 ; right
  bit joypad1
  bne :+
  inc cursor_x
  :
  lda #%00000001 ; left
  bit joypad1
  bne :+
  dec cursor_x
  :
  lda #%00000100 ; down
  bit joypad1
  bne :+
  dec cursor_y
  :
  lda #%00001000 ; up
  bit joypad1
  bne :+
  inc cursor_y
  :
  
  ldx #$00 	; Set SPR-RAM address to 0
  stx $2003 ; OAM ADDR
  lda #$20; Y
  clc
  adc cursor_y
  sta $2004
  clc
  lda joypad1 ;
  adc #$30 ;

  sta $2004
  lda #$00 ; Attr
  sta $2004
  lda #$20 ; X
  clc
  adc cursor_x
  sta $2004


  lda #$20; Y
  sta $2004
  clc
  lda joypad2 ;
  adc #$30 ;

  sta $2004
  lda #$00 ; Attr
  sta $2004
  lda #$60 ; X
  sta $2004

  rti

sprites: ; Y   TileNo   Attr  X
  ; .byte $6c, $00, $00, $6c      !;\ square at x=6C y=6C ;
  ; .byte $88, $00, $00, $88 ;
  ; .byte $80, $00, $00, $80 ;
  ; .byte $80, $00, $00, $80
  .byte $20, $24, $00, $20 ;
  .byte $20, $24, $00, $28 ;

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
  ; .byte %11111111 ;
  ; .byte %10000001 ;
  ; .byte %10000001 ;
  ; .byte %10000001 ;
  ; .byte %10000001 ;
  ; .byte %10000001 ;
  ; .byte %10000001 ;
  ; .byte %11111111 ;
  ; .byte $00, $00, $00, $00, $00, $00, $00, $00 !;\ Second plane ;

  ; .byte %10000001 ;
  ; .byte %01000010 ;
  ; .byte %00100100 ;
  ; .byte %00011000 ;
  ; .byte %00011000 ;
  ; .byte %00100100 ;
  ; .byte %01000010 ;
  ; .byte %10000001 ;
  ; .byte $00, $00, $00, $00, $00, $00, $00, $00 !;\ Second plane ;

