; Pulse-width modulation
; 03_pulse_sweep - see the matching tutorial lesson.
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
; Load literal $a2 into accumulator A; # means value, not address.
    lda #$a2 ; A3, half the A4 frequency word.
; Write A to voice 1 frequency low byte ($D400).
    sta SID
; Load literal $0e into accumulator A; # means value, not address.
    lda #$0e
; Write A to voice 1 frequency high byte ($D401).
    sta SID+1
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write A to voice 1 pulse width low byte ($D402).
    sta SID+2
; Load literal 2 into accumulator A; # means value, not address.
    lda #2
; Write A to voice 1 pulse width high nibble ($D403).
    sta SID+3
; Load literal $41 into accumulator A; # means value, not address.
    lda #$41
; Write A to voice 1 control byte ($D404).
    sta SID+4 ; Pulse plus gate.
; Load Y with 3 for the counter or index described here.
    ldy #3 ; Three gradual rising sweeps.
;
; WHAT: Start a new pulse-width sweep
; WHY: Resetting the RAM counter makes each sweep cover the same range
; HOW: Set width=2 before entering sweep
; CONTRACT: Y counts remaining sweeps; pitch and gate remain held
repeat_sweep:
; Load literal 2 into accumulator A; # means value, not address.
    lda #2
; Store A into RAM variable width so the loop can update it later.
    sta width
;
; WHAT: Advance one pulse-width position
; WHY: Small timed changes make timbre movement audible
; HOW: Write counter to hardware, wait, increment and test the end
; CONTRACT: The RAM byte owns the sweep state; delay consumes X
sweep:
; Read the RAM byte width into A without changing the stored byte.
    lda width
; Write A to voice 1 pulse width high nibble ($D403).
    sta SID+3 ; Only upper 4 bits of 12-bit width.
; Load X with 8 for the counter or index described here.
    ldx #8
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Increment the RAM counter width; Z=1 when it wraps from $FF to zero.
    inc width
; Read the RAM byte width into A without changing the stored byte.
    lda width
; Compare A with #14 without changing A; equality sets Z=1.
    cmp #14
; Branch to sweep if Z=0, so the counter has not reached its end.
    bne sweep
; Subtract one from Y; Z=1 means the sweep count reached zero.
    dey
; Branch to repeat_sweep if Z=0, so the counter has not reached its end.
    bne repeat_sweep
; Continue at finish without pushing another return address.
    jmp finish
;
; WHAT: Reserve one RAM byte for width
; WHY: SID write-only control values cannot serve as dependable storage
; HOW: !byte emits an initial zero; setup writes the intended start value
; CONTRACT: Data only; initialized before first read
width:
; Emit a zero byte: BASIC line terminator here, or initial RAM data.
    !byte 0
