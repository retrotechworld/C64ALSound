; One shared low-pass filter
; 04_filter_sweep - see the matching tutorial lesson.
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
; Load literal $c6 into accumulator A; # means value, not address.
    lda #$c6
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
; Load literal $21 into accumulator A; # means value, not address.
    lda #$21
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Bright sawtooth supplies harmonics.
; Load literal $81 into accumulator A; # means value, not address.
    lda #$81
; Write resonance in bits 7..4 and source-routing mask in bits 3..0 ($D417).
    sta SID+23 ; Resonance 8, route voice 1 only.
; Load literal $1f into accumulator A; # means value, not address.
    lda #$1f
; Write global filter modes, voice-3-off and master volume ($D418).
    sta SID+24 ; Low-pass plus volume 15.
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write A bits 0..2 as the bottom three cutoff bits ($D415).
    sta SID+21 ; Bottom three cutoff bits remain 0.
; Store A into RAM variable cutoff so the loop can update it later.
    sta cutoff
;
; WHAT: Advance one filter cutoff position
; WHY: Small timed changes make timbre movement audible
; HOW: Write counter to hardware, wait, increment and test the end
; CONTRACT: The RAM byte owns the sweep state; delay consumes X
sweep:
; Read the RAM byte cutoff into A without changing the stored byte.
    lda cutoff
; Write A as cutoff bits 3..10 ($D416); one unit here is eight cutoff units.
    sta SID+22 ; Upper eight bits of 11-bit cutoff.
; Load X with 2 for the counter or index described here.
    ldx #2
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Increment the RAM counter cutoff; Z=1 when it wraps from $FF to zero.
    inc cutoff
; Branch to sweep if Z=0, so the counter has not reached its end.
    bne sweep ; 256 steps; then stop instead of wrap.
; Continue at finish without pushing another return address.
    jmp finish
;
; WHAT: Reserve one RAM byte for cutoff
; WHY: SID write-only control values cannot serve as dependable storage
; HOW: !byte emits an initial zero; setup writes the intended start value
; CONTRACT: Data only; initialized before first read
cutoff:
; Emit a zero byte: BASIC line terminator here, or initial RAM data.
    !byte 0
