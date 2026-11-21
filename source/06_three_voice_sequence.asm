; A short melody over a two-note backing
; 06_three_voice_sequence - see the matching tutorial lesson.
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
; Each voice uses the same seven-register layout.
; Load literal $24 into accumulator A; # means value, not address.
    lda #$24
; Write A to voice 1 attack and decay nibbles ($D405).
    sta SID+5
; Write A to voice 2 attack and decay nibbles ($D40C).
    sta SID+12
; Write A to voice 3 attack and decay nibbles ($D413).
    sta SID+19
; Load literal $86 into accumulator A; # means value, not address.
    lda #$86
; Write A to voice 1 sustain and release nibbles ($D406).
    sta SID+6
; Write A to voice 2 sustain and release nibbles ($D40D).
    sta SID+13
; Write A to voice 3 sustain and release nibbles ($D414).
    sta SID+20
; Voice 2 C3=$08b3, voice 3 G3=$0d09 (PAL approximations).
; Load literal $b3 into accumulator A; # means value, not address.
    lda #$b3
; Write A to voice 2 frequency low byte ($D407).
    sta SID+7
; Load literal $08 into accumulator A; # means value, not address.
    lda #$08
; Write A to voice 2 frequency high byte ($D408).
    sta SID+8
; Load literal $09 into accumulator A; # means value, not address.
    lda #$09
; Write A to voice 3 frequency low byte ($D40E).
    sta SID+14
; Load literal $0d into accumulator A; # means value, not address.
    lda #$0d
; Write A to voice 3 frequency high byte ($D40F).
    sta SID+15
; Load literal $11 into accumulator A; # means value, not address.
    lda #$11
; Write A to voice 2 control byte ($D40B).
    sta SID+11
; Write A to voice 3 control byte ($D412).
    sta SID+18 ; Hold the backing notes.
; Load Y with 0 for the counter or index described here.
    ldy #0
;
; WHAT: Read and play one lead note
; WHY: Pitch tables separate musical data from CPU instructions
; HOW: Load matching low/high bytes, gate on, hold, gate off, wait
; CONTRACT: Y=0..7; voice 2 and voice 3 remain held
next_note:
; Read table byte at notes_lo,y into A; Y selects the current entry.
    lda notes_lo,y
; Write A to voice 1 frequency low byte ($D400).
    sta SID
; Read table byte at notes_hi,y into A; Y selects the current entry.
    lda notes_hi,y
; Write A to voice 1 frequency high byte ($D401).
    sta SID+1
; Load literal $21 into accumulator A; # means value, not address.
    lda #$21
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Start lead sawtooth.
; Load X with 18 for the counter or index described here.
    ldx #18
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Load literal $20 into accumulator A; # means value, not address.
    lda #$20
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Release lead; keep waveform selected.
; Load X with 12 for the counter or index described here.
    ldx #12
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames ; Explicit gap before retriggering.
; Add one to Y to select the next table entry.
    iny
; Compare Y with #8 without changing Y; equality sets Z=1.
    cpy #8
; Branch to next_note if Z=0, so the counter has not reached its end.
    bne next_note
; Continue at finish without pushing another return address.
    jmp finish
;
; WHAT: Store the low bytes of eight lead pitches
; WHY: The SID frequency has two eight-bit registers
; HOW: Entry N pairs with notes_hi entry N
; CONTRACT: Data only; changing table length also requires CPY adjustment
notes_lo:
; Emit literal data bytes into the PRG; CPU reads these through a table label.
    !byte $67,$1c,$f5,$1c,$67,$1c,$f5,$67
;
; WHAT: Store matching high bytes of the lead pitches
; WHY: Low and high entries must describe the same 16-bit word
; HOW: Together entries form low+256*high
; CONTRACT: Data only; the melody is PAL tuned
notes_hi:
; Emit literal data bytes into the PRG; CPU reads these through a table label.
    !byte $11,$16,$19,$16,$11,$16,$19,$11
