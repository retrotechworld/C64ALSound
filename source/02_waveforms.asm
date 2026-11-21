; Triangle, saw, pulse and noise
; 02_waveforms - see the matching tutorial lesson.
; HOW: Assemble common startup here, then this lesson body.
!source "source/common.asm"

; BEGINNER READING GUIDE - WHAT / WHY / HOW
; WHAT: One runnable SID listening lesson.
; WHY: Understand the sound design as well as each CPU operation.
; HOW: Follow start -> init_sid -> voice setup -> loop -> finish.
; See the tutorial for the matching trace and listening experiment.
; CPU: 6510 using standard 6502 instructions. Assembler: ACME.
; REQUIREMENTS: I/O visible; standard C64 display running; normal stack.
; TIMING: PAL note tables; NTSC pitch and duration need adjustment.
; STATUS: Reviewed teaching source; assembly and listening not verified.
;
;
; WHAT: Set up this lesson and begin playback
; WHY: The SID has no single command that creates a complete instrument
; HOW: Initialise globals, configure the voice, then raise its gate
; CONTRACT: Called through SYS 4096; uses standard BASIC memory mapping
start:
; Call init_sid; CPU pushes a return address, and RTS resumes here.
    jsr init_sid
; Load literal $04 into accumulator A; # means value, not address.
    lda #$04
; Write A to voice 1 attack and decay nibbles ($D405).
    sta SID+5 ; Fast attack, moderate decay.
; Load literal $a6 into accumulator A; # means value, not address.
    lda #$a6
; Write A to voice 1 sustain and release nibbles ($D406).
    sta SID+6
; Load literal $44 into accumulator A; # means value, not address.
    lda #$44
; Write A to voice 1 frequency low byte ($D400).
    sta SID
; Load literal $1d into accumulator A; # means value, not address.
    lda #$1d
; Write A to voice 1 frequency high byte ($D401).
    sta SID+1
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write A to voice 1 pulse width low byte ($D402).
    sta SID+2
; Load literal 8 into accumulator A; # means value, not address.
    lda #8
; Write A to voice 1 pulse width high nibble ($D403).
    sta SID+3 ; $800 pulse width: approximately 50%.
; Load Y with 0 for the counter or index described here.
    ldy #0
;
; WHAT: Play the waveform selected by Y
; WHY: One loop makes comparison use the same pitch and envelope
; HOW: Read waves,Y, hold, release, then advance Y
; CONTRACT: Y=0..3; delay routines preserve Y
next_wave:
; Read table byte at waves,y into A; Y selects the current entry.
    lda waves,y ; Read waveform byte from RAM table.
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; All entries include gate=1.
; Load X with 75 for the counter or index described here.
    ldx #75
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Gate off before the next example.
; Load X with 30 for the counter or index described here.
    ldx #30
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Add one to Y to select the next table entry.
    iny
; Compare Y with #4 without changing Y; equality sets Z=1.
    cpy #4
; Branch to next_wave if Z=0, so the counter has not reached its end.
    bne next_wave
; Continue at finish without pushing another return address.
    jmp finish
;
; WHAT: Store waveform control bytes
; WHY: A table is simpler to edit than four copies of playback code
; HOW: Each byte combines one waveform bit with gate=1
; CONTRACT: Data only; indexed by LDA waves,Y
waves:
; Emit literal data bytes into the PRG; CPU reads these through a table label.
    !byte $11,$21,$41,$81
