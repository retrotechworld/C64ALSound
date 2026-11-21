; First note: A4 triangle
; 01_first_note - see the matching tutorial lesson.
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
; Load literal $24 into accumulator A; # means value, not address.
    lda #$24 ; A=2 attack, D=4 decay.
; Write A to voice 1 attack and decay nibbles ($D405).
    sta SID+5
; Load literal $a6 into accumulator A; # means value, not address.
    lda #$a6 ; S=10 level, R=6 release.
; Write A to voice 1 sustain and release nibbles ($D406).
    sta SID+6
; Load literal $44 into accumulator A; # means value, not address.
    lda #$44 ; PAL A4: word $1d44 = 7492.
; Write A to voice 1 frequency low byte ($D400).
    sta SID+0 ; Low frequency byte.
; Load literal $1d into accumulator A; # means value, not address.
    lda #$1d
; Write A to voice 1 frequency high byte ($D401).
    sta SID+1 ; High frequency byte.
; Load literal $11 into accumulator A; # means value, not address.
    lda #$11 ; Triangle ($10) plus gate ($01).
; Write A to voice 1 control byte ($D404).
    sta SID+4
; Load X with 100 for the counter or index described here.
    ldx #100 ; About 2 seconds PAL, 1.67 NTSC.
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Continue at finish without pushing another return address.
    jmp finish
