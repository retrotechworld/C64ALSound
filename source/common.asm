; BEGINNER READING GUIDE - WHAT / WHY / HOW
; WHAT: Shared startup, reset, timing and cleanup.
; WHY: Understand the sound design as well as each CPU operation.
; HOW: Follow start -> init_sid -> voice setup -> loop -> finish.
; See the tutorial for the matching trace and listening experiment.
; CPU: 6510 using standard 6502 instructions. Assembler: ACME.
; REQUIREMENTS: I/O visible; standard C64 display running; normal stack.
; TIMING: PAL note tables; NTSC pitch and duration need adjustment.
; STATUS: Reviewed teaching source; assembly and listening not verified.
;
; Shared ACME routines. Build directly with ACME; working directory is the package root.
; All examples enter at $1000 through the BASIC SYS stub.
; Name the hardware base address; this constant allocates no RAM.
SID = $d400
; Set the assembler program counter; following bytes are placed at $0801.
* = $0801
; BASIC next-line pointer, stored low byte first by !word.
!word basic_end
; BASIC line number 10, stored as a two-byte little-endian value.
!word 10
; BASIC token $9E means SYS.
!byte $9e
; Emit the ASCII digits of decimal 4096 as BASIC line text.
!text "4096"
; Emit a zero byte: BASIC line terminator here, or initial RAM data.
!byte 0
;
; WHAT: Terminate the BASIC program
; WHY: BASIC follows linked line pointers until a zero pointer
; HOW: Emit a final two-byte zero after the SYS line
; CONTRACT: Assembler label; BASIC data, not an executed machine instruction
basic_end:
; Two zero bytes terminate the BASIC linked list.
!word 0
; Set the assembler program counter; following bytes are placed at $1000.
* = $1000
; Continue at start without pushing another return address.
    jmp start

;
; WHAT: Initialise a known sound state
; WHY: Old register values can leave a filter, TEST or gate active
; HOW: Clear offsets 24 through 0, then select full master volume
; CONTRACT: No input; A and X changed; SID writable registers replaced
init_sid:
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Load X with 24 for the counter or index described here.
    ldx #24 ; Only the 25 writable SID registers.
;
; WHAT: Clear one register per pass
; WHY: Every voice and global setting needs a defined value
; HOW: Store zero at SID+X, decrement X and repeat through X=0
; CONTRACT: A must remain zero; X begins at 24; exits with X=$FF
clear_sid:
; Write A to SID base plus X; visits one writable register per loop.
    sta SID,x
; Subtract one from X; updates N and Z flags for the following branch.
    dex
; Branch to clear_sid if N=0; interpret the preceding instruction's result.
    bpl clear_sid
; Load literal 15 into accumulator A; # means value, not address.
    lda #15
; Write global filter modes, voice-3-off and master volume ($D418).
    sta SID+24 ; No filter modes, master volume 15.
; Pull the saved return address and resume the caller.
    rts

;
; WHAT: Wait for the next raster boundary
; WHY: A stable frame boundary provides simple audible durations
; HOW: Save A, leave the high-raster region, then wait for the next one
; CONTRACT: No input; preserves A, X and Y; flags changed; blocks
wait_frame:
; Wait for the next entrance to raster line 256. $d011 bit 7 is
; the live ninth raster bit when READ. No raster IRQ is installed.
; Standard PAL and NTSC C64 displays both reach line 256.
; Push A on the stack so the raster wait may use A temporarily.
    pha ; Preserve A because callers may hold a value.
;
; WHAT: Wait until raster bit 8 is zero
; WHY: Entering halfway through the high region must not count twice
; HOW: Read $D011 and repeat while bit 7 is set
; CONTRACT: A is temporary; saved by wait_frame; uses the N flag
wait_low:
; Read VIC-II raster high bit into A; bit 7 sets CPU N flag.
    lda $d011
; Branch to wait_low if N=1; for $D011 this means raster lines 256 or above.
    bmi wait_low ; Leave the previous high-raster region.
;
; WHAT: Wait until raster bit 8 becomes one
; WHY: This transition marks the next entry to line 256
; HOW: Repeat while the sign bit is clear; then restore A
; CONTRACT: Caller must enter from the low region; no IRQ is installed
wait_high:
; Read VIC-II raster high bit into A; bit 7 sets CPU N flag.
    lda $d011
; Branch to wait_high if N=0; interpret the preceding instruction's result.
    bpl wait_high ; Enter the next high-raster region.
; Pull the saved A from the stack; balances the earlier PHA.
    pla
; Pull the saved return address and resume the caller.
    rts

;
; WHAT: Count X display frames
; WHY: All lessons need readable duration units
; HOW: Call wait_frame, decrement X and loop until X=0
; CONTRACT: X=1..255; returns X=0; A and Y preserved; flags changed
wait_frames:
; X is the number of frames (1..255). A is preserved, X becomes 0.
; Call wait_frame; CPU pushes a return address, and RTS resumes here.
    jsr wait_frame
; Subtract one from X; updates N and Z flags for the following branch.
    dex
; Branch to wait_frames if Z=0, so the counter has not reached its end.
    bne wait_frames
; Pull the saved return address and resume the caller.
    rts

;
; WHAT: Release, mute and return to BASIC
; WHY: Abruptly cutting master volume can truncate a release tail
; HOW: Clear controls, allow 60 frames, then mute master volume
; CONTRACT: Reached with JMP from a lesson; uses original SYS return address
finish:
; Let the envelope release before master volume is muted.
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write A to voice 1 control byte ($D404).
    sta SID+4
; Write A to voice 2 control byte ($D40B).
    sta SID+11
; Write A to voice 3 control byte ($D412).
    sta SID+18
; Load X with 60 for the counter or index described here.
    ldx #60
; Call wait_frames; CPU pushes a return address, and RTS resumes here.
    jsr wait_frames
; Load literal 0 into accumulator A; # means value, not address.
    lda #0
; Write global filter modes, voice-3-off and master volume ($D418).
    sta SID+24
; Pull the saved return address and resume the caller.
    rts ; Return to BASIC's SYS caller.
