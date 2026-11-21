; Ring modulation and hard sync
; 05_ring_sync - see the matching tutorial lesson.
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
    sta SID+5
; Load literal $b6 into accumulator A; # means value, not address.
    lda #$b6
; Write A to voice 1 sustain and release nibbles ($D406).
    sta SID+6
; Load literal $44 into accumulator A; # means value, not address.
    lda #$44
; Write A to voice 1 frequency low byte ($D400).
    sta SID
; Load literal $1d into accumulator A; # means value, not address.
    lda #$1d
; Write A to voice 1 frequency high byte ($D401).
    sta SID+1 ; Voice 1 audible carrier.
; Load literal $00 into accumulator A; # means value, not address.
    lda #$00
; Write A to voice 3 frequency low byte ($D40E).
    sta SID+14
; Load literal $08 into accumulator A; # means value, not address.
    lda #$08
; Write A to voice 3 frequency high byte ($D40F).
    sta SID+15 ; Voice 3 oscillator drives voice 1.
; Voice 3 has no waveform, no gate, no sustain: it is inaudible,
; but its phase accumulator still runs (TEST is zero).
; Load literal $15 into accumulator A; # means value, not address.
    lda #$15
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Triangle + ring + gate.
; Load X with 150 for the counter or index described here.
    ldx #150
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Load literal $10 into accumulator A; # means value, not address.
    lda #$10
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Gate off while keeping triangle.
; Load X with 30 for the counter or index described here.
    ldx #30
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Load literal $23 into accumulator A; # means value, not address.
    lda #$23
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Saw + sync + gate, ring disabled.
; Load X with 150 for the counter or index described here.
    ldx #150
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Continue at finish without pushing another return address.
    jmp finish
