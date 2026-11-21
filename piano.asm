; ----------------------------------------------------------------------------
; SID PIANO: A THREE-VOICE C64 INSTRUMENT
; ACME source, loaded by BASIC RUN / SYS 2061 ($080d).
;
; WHAT: A/W/S/E/D/F/T/G/Y/H/U/J/K play thirteen chromatic notes C..C.
; WHY: Direct matrix scanning preserves simultaneous held-key state; GETIN
;      provides character events and is unsuitable for sustained chords.
; HOW: Each frame scans CIA1, changes octave on a new 1/2 press, releases old
;      voice assignments, allocates free voices, writes SID pitch/gate, then
;      colours the character-graphics keys. The SID synthesises between frames.
;
; DATA MODEL:
;   held[13]   = 0 if released; otherwise a nonzero keyboard bit mask.
;   voices[3]  = note index 0..12, or $ff when available for allocation.
;   octave     = 0,1,2 for C3..C4, C4..C5, C5..C6 respectively.
;   table index = note index + octave_offsets[octave] (range 0..36).
;
; ENVIRONMENT: Stock BASIC/KERNAL startup, I/O visible, normal VIC bank DDR.
; SEI disables maskable IRQ handling while we own the keyboard. It does not
; disable NMI (RESTORE) or VIC badline/DMA activity. This is a standalone demo,
; not a drop-in IRQ music driver. $fb/$fc are temporary zero-page pointers.
; The exit restores selected CIA registers, not a complete machine snapshot.
;
; See TUTORIAL.md for the guided lesson, exercises and hardware references.
; ----------------------------------------------------------------------------

; Emit a CBM PRG with a two-byte little-endian load-address header.
!to "piano.prg", cbm
; Place a tokenised BASIC line at the usual C64 BASIC start address.
* = $0801
; Next BASIC line=$080b, line number=10, token $9e=SYS.
!byte $0b,$08,$0a,$00,$9e
; BASIC reads decimal SYS address 2061, which equals $080d.
!text "2061"
; Terminate the line text, then the BASIC program link ($0000).
!byte 0,0,0
; Place machine code exactly where the BASIC SYS stub expects it.
* = $080d

; ----------------------------------------------------------------------------
; TAKE CONTROL OF KEYBOARD, SOUND AND DISPLAY
; Save the CIA state that this program changes. Port A selects keyboard
; columns as outputs; port B reads the switches as inputs. IRQs are masked
; so the KERNAL keyboard scanner cannot change these ports during our scan.
; ----------------------------------------------------------------------------
start:
; Mask IRQs to keep the KERNAL scanner out of our CIA accesses.
    sei
; Read CIA1 port-A direction bits.
    lda $dc02
; Remember the original direction register.
    sta old_ddra
; Read CIA1 port-B direction bits.
    lda $dc03
; Remember the original input/output arrangement.
    sta old_ddrb
; Read the current CIA1 port-A value.
    lda $dc00
; Save it for exit; this is a port read, not a full CIA snapshot.
    sta old_port
; Select all eight bits as outputs.
    lda #$ff
; Apply output direction to the keyboard column port.
    sta $dc02
; Zero will mean all inputs, black colour, and cleared SID registers.
    lda #0
; Make all port-B bits inputs.
    sta $dc03
; Set the VIC border to black.
    sta $d020
; Set the screen background to black.
    sta $d021
; Begin at SID offset 24, the master-volume register.
    ldx #24

; ----------------------------------------------------------------------------
; RESET THE SID TO A KNOWN STATE
; Clear offsets 24 down to 0 inclusive: $d400..$d418. This includes
; oscillator controls, envelope settings, filter routing and master volume.
; Then enable volume; no gate is enabled until a note has an assigned voice.
; ----------------------------------------------------------------------------
clear_sid:
; Write zero; A remains zero throughout this loop.
    sta $d400,x
; Move to the preceding SID register.
    dex
; Continue while X is 24..0; stop when it underflows to $ff.
    bpl clear_sid
; Master-volume level 15, with the upper control bits clear.
    lda #15
; Enable the maximum SID master level.
    sta $d418
; Enable the display, 25 rows, standard text mode and vertical scroll 3.
    lda #$1b
; Apply the normal text display control value.
    sta $d011
; 40 columns, horizontal scroll 0, multicolour text off.
    lda #8
; Apply the horizontal display setting.
    sta $d016
; Screen offset $0400 and character-ROM offset $1000 in the VIC bank.
    lda #$14
; Select the screen and character set addresses.
    sta $d018
; Read CIA2 port A, which includes VIC bank selection.
    lda $dd00
; Save it before changing the bank bits.
    sta old_bank
; Set inverted VIC bank bits 0..1 to 11; preserve other port bits.
    ora #3
; Select VIC bank $0000..$3fff under normal CIA2 DDR setup.
    sta $dd00
; Start a 256-iteration screen-copy loop at byte index zero.
    ldx #0

; ----------------------------------------------------------------------------
; COPY FOUR PAGES WITH ONE 8-BIT INDEX
; X wraps through 0..255. Four stores per iteration copy 1024 bytes.
; The visible 40x25 screen uses 1000 bytes; the last 24 are padding. Colours
; are set independently because screen RAM stores glyphs, not ink colours.
; ----------------------------------------------------------------------------
copy_screen:
; Read page 0 of the prepared screen.
    lda screen,x
; Copy it to screen page $0400.
    sta $0400,x
; Read page 1 of the prepared screen.
    lda screen+256,x
; Copy it to screen page $0500.
    sta $0500,x
; Read page 2 of the prepared screen.
    lda screen+512,x
; Copy it to screen page $0600.
    sta $0600,x
; Read page 3, including the final 24 padding bytes.
    lda screen+768,x
; Copy it to screen page $0700.
    sta $0700,x
; Choose light grey (colour 15) for the initial screen.
    lda #15
; Colour page 0.
    sta $d800,x
; Colour page 1.
    sta $d900,x
; Colour page 2.
    sta $da00,x
; Colour page 3, including non-visible padding.
    sta $db00,x
; Increment X; 255 wraps to zero.
    inx
; Repeat until the index wraps, completing all four pages.
    bne copy_screen
; Initialise logical voices 2, 1, 0 in descending order.
    ldx #2

; ----------------------------------------------------------------------------
; CONFIGURE THE THREE ENVELOPES
; Logical voice X maps to a SID byte offset through offsets[X].
; $08 means attack 0 / decay 8. $a8 means sustain 10 / release 8.
; Sustain is a LEVEL, not a time. Gate is initially off after clear_sid.
; ----------------------------------------------------------------------------
init_voice:
; $ff is the unassigned-voice sentinel.
    lda #$ff
; Mark voices[X] free.
    sta voices,x
; Translate logical voice X to SID offset 0, 7 or 14.
    ldy offsets,x
; Attack nibble 0; decay nibble 8.
    lda #$08
; Write this voice attack/decay register.
    sta $d405,y
; Sustain nibble $a; release nibble 8.
    lda #$a8
; Write this voice sustain/release register.
    sta $d406,y
; Move to the preceding voice.
    dex
; Repeat through voice 0; then fall through into main.
    bpl init_voice

; ----------------------------------------------------------------------------
; FRAME-BASED APPLICATION LOOP
; Wait for raster-low value 250, then wait for that line to end.
; Reading only $d012 ignores raster bit 8, but both standard PAL and NTSC
; frames reach line 250 once. There is no second line 506 on either system.
; The wait is approximate synchronisation, not a cycle-stable raster IRQ.
; ----------------------------------------------------------------------------
main:
; Keep target raster value 250 in A.
    lda #250

; ----------------------------------------------------------------------------
; WAIT UNTIL THE BEAM REACHES LINE 250
; CMP leaves A unchanged, so A remains the reference raster value.
; ----------------------------------------------------------------------------
wait_frame:
; Compare the current low raster byte with the target.
    cmp $d012
; Keep waiting until they match.
    bne wait_frame

; ----------------------------------------------------------------------------
; DO INPUT, SOUND AND DRAWING ONCE PER FRAME
; Leaving the line avoids executing multiple updates while the beam
; is still on line 250. The full update takes less than a video frame.
; ----------------------------------------------------------------------------
leave_line:
; Compare again while A still contains 250.
    cmp $d012
; Wait until the beam moves on.
    beq leave_line
; Populate matrix[] and held[] from all keyboard switches.
    jsr scan
; Read keyboard column 7.
    lda matrix+7
; Keep only PB7, the RUN/STOP switch.
    and #$80
; Exit when the pressed-bit representation has bit 7 set.
    bne exit
; Handle new presses of the octave-control keys.
    jsr octave_keys
; Release, allocate and update the three SID voices.
    jsr update_voices
; Reflect the octave and note states on screen.
    jsr draw_keys
; Return to the next raster wait.
    jmp main

; ----------------------------------------------------------------------------
; STOP SOUND AND RETURN TO BASIC
; Clear SID immediately, restore the saved keyboard/bank settings,
; clear the KERNAL character queue and clear the screen. CLI then restores
; normal maskable IRQ handling. RTS returns to the BASIC SYS caller.
; This does not restore previous sound, VIC settings, colours or $fb/$fc.
; ----------------------------------------------------------------------------
exit:
; Start clearing at SID register offset 24.
    ldx #24
; Use zero for every sound-register write.
    lda #0

; ----------------------------------------------------------------------------
; CLEAR ALL WRITABLE SOUND REGISTERS
; Unlike a normal note release, setting volume to zero cuts off all
; remaining envelope tails immediately. This is deliberate on program exit.
; ----------------------------------------------------------------------------
silence:
; Clear the current SID register, including master volume.
    sta $d400,x
; Move towards offset 0.
    dex
; Continue until every writable SID register has been cleared.
    bpl silence
; Recover saved CIA2 port-A value.
    lda old_bank
; Restore the bank-selection port value.
    sta $dd00
; Recover saved CIA1 port-A read value.
    lda old_port
; Restore the keyboard port before restoring its direction.
    sta $dc00
; Recover original CIA1 port-A directions.
    lda old_ddra
; Restore those direction bits.
    sta $dc02
; Recover original CIA1 port-B directions.
    lda old_ddrb
; Restore those direction bits.
    sta $dc03
; Prepare an empty KERNAL keyboard queue.
    lda #0
; Store zero in decimal 198 ($c6), its character count.
    sta 198
; Call the standard KERNAL ROM screen-clear implementation.
    jsr $e544
; Allow normal IRQ handling again.
    cli
; Return to BASIC through the SYS return address.
    rts

; ----------------------------------------------------------------------------
; READ ALL EIGHT KEYBOARD COLUMNS
; A key connects a selected CIA1 port-A line to a port-B input.
; Electrical reads are active-low: invert them to make pressed bits 1.
; ----------------------------------------------------------------------------
scan:
; Start with keyboard column 0.
    ldx #0

; ----------------------------------------------------------------------------
; SELECT ONE COLUMN AND SAMPLE ITS ROW BITS
; Two NOPs add a short settling interval between driving the column
; and reading the inputs. No attempt is made to correct keyboard ghosting.
; ----------------------------------------------------------------------------
scan_column:
; Fetch a mask with exactly one zero bit.
    lda column_masks,x
; Drive that one keyboard column low.
    sta $dc00
; Allow two CPU cycles for signals to settle.
    nop
; Allow two more settling cycles.
    nop
; Read the eight port-B input bits.
    lda $dc01
; Invert active-low inputs so a pressed switch gives a 1.
    eor #$ff
; Save all eight pressed bits for this column.
    sta matrix,x
; Select the next column index.
    inx
; Have all eight columns been sampled?
    cpx #8
; Repeat until X reaches 8.
    bne scan_column
; Prepare to deselect every column.
    lda #$ff
; Drive all port-A column lines high.
    sta $dc00
; Decode note indices 12 down to 0.
    ldx #12

; ----------------------------------------------------------------------------
; TRANSLATE MATRIX POSITIONS INTO MUSICAL ORDER
; The screen, voice allocator and tuning tables all use semitone
; indices. note_columns and note_masks translate those indices to switches.
; Store the masked value directly: later code tests zero versus nonzero.
; ----------------------------------------------------------------------------
scan_note:
; Find which scanned column contains musical note X.
    ldy note_columns,x
; Load that column pressed-bit byte.
    lda matrix,y
; Keep only this note switch bit.
    and note_masks,x
; Save zero or the bit mask, not a normalised Boolean 1.
    sta held,x
; Go down one semitone index.
    dex
; Continue through note 0.
    bpl scan_note
; Return with fresh held-key state.
    rts

; ----------------------------------------------------------------------------
; EDGE DETECTION FOR 1 AND 2
; bits 0 and 3 of matrix[7] are 1 and 2. Formula:
; rising = (current XOR previous) AND current. Holding a button therefore
; changes octave once. This detects transitions; it is not switch debounce.
; If both rising bits occur together ($09), neither direction is taken.
; ----------------------------------------------------------------------------
octave_keys:
; Load the column shared by 1 and 2.
    lda matrix+7
; Keep PB0 ($01) and PB3 ($08) only.
    and #9
; Save the current two-button state.
    sta buttons
; Find bits whose state changed since the preceding frame.
    eor previous_buttons
; Keep changed bits that are down now: rising edges.
    and buttons
; Remember the new-press mask.
    sta edges
; Reload this frame button state.
    lda buttons
; Make it next frame previous state.
    sta previous_buttons
; Load only the newly pressed bits.
    lda edges
; Was 1 the only newly pressed button?
    cmp #1
; Otherwise consider the up direction.
    bne try_up
; Read the selected octave window.
    lda octave
; At zero we are already at the bottom range.
    beq octave_done
; Move down exactly one octave window.
    dec octave
; Return immediately after handling down.
    rts

; ----------------------------------------------------------------------------
; CHECK THE UP BUTTON AND UPPER LIMIT
; The lower path has already returned if it changed octave.
; Only a newly pressed 2 ($08) can increase the range, up to octave=2.
; ----------------------------------------------------------------------------
try_up:
; Was 2 the only newly pressed button?
    cmp #8
; Ignore no edge or simultaneous new edges.
    bne octave_done
; Read the selected octave window.
    lda octave
; Two is the highest allowed window index.
    cmp #2
; Do nothing when already at the upper limit.
    beq octave_done
; Move up exactly one window.
    inc octave

; ----------------------------------------------------------------------------
; RETURN WITHOUT ANOTHER CHANGE
; The octave variable always stays within 0..2 in normal execution.
; ----------------------------------------------------------------------------
octave_done:
; Return with octave still in the valid range.
    rts

; ----------------------------------------------------------------------------
; PASS 1: RELEASE ASSIGNMENTS THAT ARE NO LONGER HELD
; Keep existing held notes on their voices. Rebuilding every voice
; assignment each frame would cause unnecessary gate changes and disturb
; envelopes. Releasing first makes freed voices available in the same frame.
; ----------------------------------------------------------------------------
update_voices:
; Start the release pass with logical voice 2.
    ldx #2

; ----------------------------------------------------------------------------
; TEST ONE EXISTING VOICE
; X is the logical voice; Y is its note index until converted to a
; hardware offset. Always check the $ff sentinel BEFORE indexing held[].
; ----------------------------------------------------------------------------
release_loop:
; Fetch the note currently owned by voice X.
    ldy voices,x
; Check for the unused-slot marker.
    cpy #$ff
; An unused voice has no held[] element to test.
    beq release_next
; Look up whether its assigned note remains held.
    lda held,y
; Leave the assignment and gate intact if it is held.
    bne release_next
; Prepare the free-slot marker.
    lda #$ff
; Return this voice slot to the allocation pool.
    sta voices,x
; Convert logical voice X to a SID register offset.
    ldy offsets,x
; Triangle remains selected; bit 0 (gate) is clear.
    lda #$10
; Begin the envelope release phase for this voice.
    sta $d404,y

; ----------------------------------------------------------------------------
; ADVANCE THROUGH THE THREE VOICES
; After X=0, DEX produces $ff (negative), so BPL finishes the loop.
; Then switch X to a note index for the allocation pass.
; ----------------------------------------------------------------------------
release_next:
; Move to the preceding voice.
    dex
; Repeat until X underflows after voice 0.
    bpl release_loop
; Start the allocation pass at the lowest note.
    ldx #0

; ----------------------------------------------------------------------------
; PASS 2: ASSIGN HELD NOTES TO AVAILABLE VOICES
; Walk notes from 0 to 12. Skip released notes and notes already
; assigned. The lowest available note wins when several waiting notes
; compete. There is no note stealing and no queue ordered by press time.
; ----------------------------------------------------------------------------
allocate_note:
; Fetch the current held state for note X.
    lda held,x
; Skip this note when released.
    beq allocate_next
; Put the candidate note index in A.
    txa
; Does voice 0 already own it?
    cmp voices
; If so, preserve that assignment.
    beq allocate_next
; Does voice 1 already own it?
    cmp voices+1
; If so, preserve that assignment.
    beq allocate_next
; Does voice 2 already own it?
    cmp voices+2
; If so, preserve that assignment.
    beq allocate_next
; Search from logical voice 0 for an available slot.
    ldy #0

; ----------------------------------------------------------------------------
; FIND THE FIRST $FF VOICE SLOT
; Y is a logical voice index 0..2, not a SID register offset.
; If all slots are busy, leave this held note waiting (yellow on screen).
; ----------------------------------------------------------------------------
find_free:
; Read the candidate voice assignment.
    lda voices,y
; Is the slot unused?
    cmp #$ff
; Assign the note if this slot is free.
    beq assign
; Try the next logical voice.
    iny
; Three means we checked slots 0, 1 and 2.
    cpy #3
; Keep looking while Y is below 3.
    bne find_free
; CPY set Z on Y=3; all voices busy, so skip this note.
    beq allocate_next

; ----------------------------------------------------------------------------
; RECORD OWNERSHIP WITHOUT TOUCHING THE GATE YET
; This voice will receive its frequency during the sound pass.
; Delaying gate-on until then avoids starting the attack at an old pitch.
; ----------------------------------------------------------------------------
assign:
; Recover the note index from X.
    txa
; Make logical voice Y own this note index.
    sta voices,y

; ----------------------------------------------------------------------------
; FINISH ALLOCATION, THEN VISIT EACH SID VOICE
; The allocator has no separate note-on event list: held[] plus
; voices[] are enough to decide what must remain, stop or start.
; ----------------------------------------------------------------------------
allocate_next:
; Move to the next semitone.
    inx
; Thirteen means notes 0..12 have all been considered.
    cpx #13
; Repeat for each possible piano key.
    bne allocate_note
; Start the hardware-write pass at logical voice 0.
    ldx #0

; ----------------------------------------------------------------------------
; PASS 3: TRANSLATE EACH ASSIGNED NOTE INTO A SID PITCH
; Add a semitone offset for the selected octave, then select the
; PAL or NTSC frequency table using the KERNAL startup flag at $02a6.
; Existing gates are not toggled off here, so a held note keeps its envelope
; when the octave changes. It transposes without a fresh attack.
; ----------------------------------------------------------------------------
sound_loop:
; Get the note index assigned to this voice.
    ldy voices,x
; Check the unused-slot sentinel.
    cpy #$ff
; Do not restart an unassigned voice.
    beq sound_next
; Transfer the note index to A.
    tya
; Use the octave-window index to address the offsets table.
    ldy octave
; Clear carry so ADC performs plain addition without an extra 1.
    clc
; Add 0, 12 or 24 semitones.
    adc octave_offsets,y
; Use the resulting 0..36 index for the pitch tables.
    tay
; Read KERNAL video flag: 0 NTSC, nonzero PAL.
    lda $02a6
; Choose the NTSC table if the flag is zero.
    beq ntsc
; Fetch the PAL tuning-word low byte.
    lda pal_lo,y
; Keep it safe while A is used for the high byte.
    sta frequency
; Fetch the PAL tuning-word high byte.
    lda pal_hi,y
; Both table paths share the actual SID stores.
    jmp write_frequency

; ----------------------------------------------------------------------------
; LOAD THE NTSC PITCH WORD
; NTSC has a faster SID clock, so the same musical pitch uses a
; smaller tuning word. Low byte goes in a temporary; high byte remains in A.
; ----------------------------------------------------------------------------
ntsc:
; Fetch the NTSC tuning-word low byte.
    lda ntsc_lo,y
; Keep it in the shared low-byte temporary.
    sta frequency
; Fetch the NTSC tuning-word high byte.
    lda ntsc_hi,y

; ----------------------------------------------------------------------------
; WRITE PITCH FIRST, THEN ENABLE TRIANGLE AND GATE
; SID registers are grouped in seven-byte blocks. Y is now 0,7,14.
; High and low frequency registers form one 16-bit tuning word. The program
; writes high first and low second; the SID does not latch this atomically.
; $11 = triangle ($10) plus gate ($01). Rewriting an already-high gate does
; not itself create another low-to-high transition or restart each attack.
; ----------------------------------------------------------------------------
write_frequency:
; Convert voice X to its hardware register-block offset.
    ldy offsets,x
; Write the high byte of this voice frequency word.
    sta $d401,y
; Recover the low byte from the temporary.
    lda frequency
; Write the low byte of this voice frequency word.
    sta $d400,y
; Select triangle and assert gate.
    lda #$11
; Enable or maintain this voice gate without a per-frame retrigger.
    sta $d404,y

; ----------------------------------------------------------------------------
; MOVE TO THE NEXT LOGICAL VOICE
; Free voices are skipped, allowing their SID release tails to decay.
; A free slot means reusable, not necessarily acoustically silent.
; ----------------------------------------------------------------------------
sound_next:
; Move to the next logical voice.
    inx
; Have all three voices been visited?
    cpx #3
; Continue until X reaches 3.
    bne sound_loop
; Return after the sound update.
    rts

; ----------------------------------------------------------------------------
; UPDATE THE OCTAVE RANGE AND KEY COLOURS
; Digits have screen codes $30..$39. Adding $33 produces 3,4,5.
; The display shows the starting octave and the next C one octave above.
; Screen addresses use base + row*40 + column, with zero-based coordinates.
; ----------------------------------------------------------------------------
draw_keys:
; Get octave-window index 0, 1 or 2.
    lda octave
; Clear carry before converting it to a screen digit.
    clc
; Add screen code for digit 3.
    adc #$33
; Replace the first octave digit at row 4, column 19.
    sta $0400+4*40+19
; Clear carry before computing the next digit.
    clc
; The top C belongs to the next numbered octave.
    adc #1
; Replace the second octave digit at row 4, column 24.
    sta $0400+4*40+24
; Paint all thirteen keys, starting with note 12.
    ldx #12

; ----------------------------------------------------------------------------
; CHOOSE WHITE, YELLOW OR GREEN
; White=not held; yellow=held without a voice; green=assigned.
; Green represents the voice state, not proof that an emulator audio device
; is playing. A released key turns white even while its release tail sounds.
; ----------------------------------------------------------------------------
draw_loop:
; Default foreground colour is white (1).
    lda #1
; Loading Y sets Z according to whether this key is held.
    ldy held,x
; Use white when its held value is zero.
    beq choose_colour
; A held key defaults to yellow (7) while waiting.
    lda #7
; Compare note index X with voice 0 owner.
    cpx voices
; Use green if voice 0 owns this note.
    beq sounding
; Compare with voice 1 owner.
    cpx voices+1
; Use green if voice 1 owns this note.
    beq sounding
; Compare with voice 2 owner.
    cpx voices+2
; If none owns it, retain yellow; otherwise fall through to green.
    bne choose_colour

; ----------------------------------------------------------------------------
; MARK AN ASSIGNED HELD NOTE GREEN
; Every one of the three voice slots has been checked for this note.
; ----------------------------------------------------------------------------
sounding:
; Choose green (5) for a note assigned to a SID voice.
    lda #5

; ----------------------------------------------------------------------------
; PAINT A THREE-BY-THREE KEY THROUGH AN INDIRECT POINTER
; key_lo/key_hi give the colour-RAM address of the key top-left.
; ($fb),Y reads the 16-bit pointer from zero page $fb/$fc and adds Y.
; Three stores paint a row; offsets 40 and 80 reach the next two rows.
; Character bytes do not change: only their foreground colour changes.
; ----------------------------------------------------------------------------
choose_colour:
; Save the chosen ink colour while A builds the pointer.
    sta colour
; Get the key top-left colour address low byte.
    lda key_lo,x
; Store the pointer low byte in zero page.
    sta $fb
; Get the matching high byte.
    lda key_hi,x
; Store the pointer high byte immediately after its low byte.
    sta $fc
; Begin at the top-left cell of the 3x3 block.
    ldy #0
; Recover the chosen foreground colour.
    lda colour
; Paint row 0, column 0.
    sta ($fb),y
; Move one column right.
    iny
; Paint row 0, column 1.
    sta ($fb),y
; Move one more column right.
    iny
; Paint row 0, column 2.
    sta ($fb),y
; Offset 40 is one complete screen row down.
    ldy #40
; Paint row 1, column 0.
    sta ($fb),y
; Move one column right.
    iny
; Paint row 1, column 1.
    sta ($fb),y
; Move one more column right.
    iny
; Paint row 1, column 2.
    sta ($fb),y
; Offset 80 is two screen rows down.
    ldy #80
; Paint row 2, column 0.
    sta ($fb),y
; Move one column right.
    iny
; Paint row 2, column 1.
    sta ($fb),y
; Move one more column right.
    iny
; Paint row 2, column 2.
    sta ($fb),y
; Move to the preceding note index.
    dex
; Repeat through note 0.
    bpl draw_loop
; Return after colouring every key.
    rts

; Saved CIA1 port-A direction register ($dc02).
old_ddra: !byte 0

; Saved CIA1 port-B direction register ($dc03).
old_ddrb: !byte 0

; Saved CIA1 port-A read value ($dc00) for normal exit.
old_port: !byte 0

; Saved CIA2 port-A value ($dd00), including VIC bank bits.
old_bank: !byte 0

; Current window 0..2; initial 1 selects C4..C5.
octave: !byte 1

; Current masked state of the two octave buttons.
buttons: !byte 0

; Previous frame state used for rising-edge detection.
previous_buttons: !byte 0

; Newly pressed octave bits; 0=none, 1=down, 8=up, 9=both.
edges: !byte 0

; Temporary low frequency byte; the high byte stays in A.
frequency: !byte 0

; Temporary foreground colour while constructing the indirect pointer.
colour: !byte 0

; Three note owners; $ff marks a reusable voice slot.
voices: !fill 3,$ff

; Thirteen switch states in semitone order: zero or a nonzero mask.
held: !fill 13,0

; Eight inverted CIA samples, one byte per scanned column.
matrix: !fill 8,0

; SID register groups are seven bytes apart; index by logical voice.
offsets: !byte 0,7,14

; Semitone offsets into the 37-note C3..C6 tuning tables.
octave_offsets: !byte 0,12,24

; Drive one port-A bit low at a time, starting with PA0.
column_masks: !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

; Port-A column index for each of the thirteen musical note indices.
note_columns: !byte 1,1,1,1,2,2,2,3,3,3,3,4,4

; Port-B row mask for each musical note; AND with matrix[column].
note_masks: !byte 4,2,32,64,4,32,64,4,2,32,64,4,32

; pal_lo: 37 low bytes in chromatic order, C3 through C6.
; N = round(note_Hz * 16777216 / SID_clock_Hz). PAL clock=985248 Hz.
; NTSC tables use 1022727 Hz. Equal temperament: A4=440 Hz,
; note_Hz = 440 * 2^((MIDI_note-69)/12), with MIDI_note=48+index.
; A table pair stores one 16-bit word as N & 255 and N >> 8.
pal_lo:
; index  0: C3; low byte of the tuning word.
    !byte 180
; index  1: C#3; low byte of the tuning word.
    !byte 56
; index  2: D3; low byte of the tuning word.
    !byte 196
; index  3: D#3; low byte of the tuning word.
    !byte 89
; index  4: E3; low byte of the tuning word.
    !byte 247
; index  5: F3; low byte of the tuning word.
    !byte 157
; index  6: F#3; low byte of the tuning word.
    !byte 78
; index  7: G3; low byte of the tuning word.
    !byte 10
; index  8: G#3; low byte of the tuning word.
    !byte 208
; index  9: A3; low byte of the tuning word.
    !byte 162
; index 10: A#3; low byte of the tuning word.
    !byte 129
; index 11: B3; low byte of the tuning word.
    !byte 109
; index 12: C4; low byte of the tuning word.
    !byte 103
; index 13: C#4; low byte of the tuning word.
    !byte 112
; index 14: D4; low byte of the tuning word.
    !byte 137
; index 15: D#4; low byte of the tuning word.
    !byte 178
; index 16: E4; low byte of the tuning word.
    !byte 237
; index 17: F4; low byte of the tuning word.
    !byte 59
; index 18: F#4; low byte of the tuning word.
    !byte 156
; index 19: G4; low byte of the tuning word.
    !byte 19
; index 20: G#4; low byte of the tuning word.
    !byte 160
; index 21: A4; low byte of the tuning word.
    !byte 69
; index 22: A#4; low byte of the tuning word.
    !byte 2
; index 23: B4; low byte of the tuning word.
    !byte 218
; index 24: C5; low byte of the tuning word.
    !byte 206
; index 25: C#5; low byte of the tuning word.
    !byte 224
; index 26: D5; low byte of the tuning word.
    !byte 17
; index 27: D#5; low byte of the tuning word.
    !byte 100
; index 28: E5; low byte of the tuning word.
    !byte 218
; index 29: F5; low byte of the tuning word.
    !byte 118
; index 30: F#5; low byte of the tuning word.
    !byte 57
; index 31: G5; low byte of the tuning word.
    !byte 38
; index 32: G#5; low byte of the tuning word.
    !byte 64
; index 33: A5; low byte of the tuning word.
    !byte 137
; index 34: A#5; low byte of the tuning word.
    !byte 4
; index 35: B5; low byte of the tuning word.
    !byte 180
; index 36: C6; low byte of the tuning word.
    !byte 156

; pal_hi: 37 high bytes in chromatic order, C3 through C6.
pal_hi:
; index  0: C3; high byte of the tuning word.
    !byte 8
; index  1: C#3; high byte of the tuning word.
    !byte 9
; index  2: D3; high byte of the tuning word.
    !byte 9
; index  3: D#3; high byte of the tuning word.
    !byte 10
; index  4: E3; high byte of the tuning word.
    !byte 10
; index  5: F3; high byte of the tuning word.
    !byte 11
; index  6: F#3; high byte of the tuning word.
    !byte 12
; index  7: G3; high byte of the tuning word.
    !byte 13
; index  8: G#3; high byte of the tuning word.
    !byte 13
; index  9: A3; high byte of the tuning word.
    !byte 14
; index 10: A#3; high byte of the tuning word.
    !byte 15
; index 11: B3; high byte of the tuning word.
    !byte 16
; index 12: C4; high byte of the tuning word.
    !byte 17
; index 13: C#4; high byte of the tuning word.
    !byte 18
; index 14: D4; high byte of the tuning word.
    !byte 19
; index 15: D#4; high byte of the tuning word.
    !byte 20
; index 16: E4; high byte of the tuning word.
    !byte 21
; index 17: F4; high byte of the tuning word.
    !byte 23
; index 18: F#4; high byte of the tuning word.
    !byte 24
; index 19: G4; high byte of the tuning word.
    !byte 26
; index 20: G#4; high byte of the tuning word.
    !byte 27
; index 21: A4; high byte of the tuning word.
    !byte 29
; index 22: A#4; high byte of the tuning word.
    !byte 31
; index 23: B4; high byte of the tuning word.
    !byte 32
; index 24: C5; high byte of the tuning word.
    !byte 34
; index 25: C#5; high byte of the tuning word.
    !byte 36
; index 26: D5; high byte of the tuning word.
    !byte 39
; index 27: D#5; high byte of the tuning word.
    !byte 41
; index 28: E5; high byte of the tuning word.
    !byte 43
; index 29: F5; high byte of the tuning word.
    !byte 46
; index 30: F#5; high byte of the tuning word.
    !byte 49
; index 31: G5; high byte of the tuning word.
    !byte 52
; index 32: G#5; high byte of the tuning word.
    !byte 55
; index 33: A5; high byte of the tuning word.
    !byte 58
; index 34: A#5; high byte of the tuning word.
    !byte 62
; index 35: B5; high byte of the tuning word.
    !byte 65
; index 36: C6; high byte of the tuning word.
    !byte 69

; ntsc_lo: 37 low bytes in chromatic order, C3 through C6.
ntsc_lo:
; index  0: C3; low byte of the tuning word.
    !byte 98
; index  1: C#3; low byte of the tuning word.
    !byte 226
; index  2: D3; low byte of the tuning word.
    !byte 105
; index  3: D#3; low byte of the tuning word.
    !byte 248
; index  4: E3; low byte of the tuning word.
    !byte 144
; index  5: F3; low byte of the tuning word.
    !byte 48
; index  6: F#3; low byte of the tuning word.
    !byte 219
; index  7: G3; low byte of the tuning word.
    !byte 143
; index  8: G#3; low byte of the tuning word.
    !byte 78
; index  9: A3; low byte of the tuning word.
    !byte 25
; index 10: A#3; low byte of the tuning word.
    !byte 240
; index 11: B3; low byte of the tuning word.
    !byte 211
; index 12: C4; low byte of the tuning word.
    !byte 196
; index 13: C#4; low byte of the tuning word.
    !byte 195
; index 14: D4; low byte of the tuning word.
    !byte 209
; index 15: D#4; low byte of the tuning word.
    !byte 240
; index 16: E4; low byte of the tuning word.
    !byte 31
; index 17: F4; low byte of the tuning word.
    !byte 97
; index 18: F#4; low byte of the tuning word.
    !byte 182
; index 19: G4; low byte of the tuning word.
    !byte 30
; index 20: G#4; low byte of the tuning word.
    !byte 157
; index 21: A4; low byte of the tuning word.
    !byte 50
; index 22: A#4; low byte of the tuning word.
    !byte 223
; index 23: B4; low byte of the tuning word.
    !byte 166
; index 24: C5; low byte of the tuning word.
    !byte 136
; index 25: C#5; low byte of the tuning word.
    !byte 134
; index 26: D5; low byte of the tuning word.
    !byte 163
; index 27: D#5; low byte of the tuning word.
    !byte 224
; index 28: E5; low byte of the tuning word.
    !byte 63
; index 29: F5; low byte of the tuning word.
    !byte 194
; index 30: F#5; low byte of the tuning word.
    !byte 107
; index 31: G5; low byte of the tuning word.
    !byte 61
; index 32: G#5; low byte of the tuning word.
    !byte 58
; index 33: A5; low byte of the tuning word.
    !byte 100
; index 34: A#5; low byte of the tuning word.
    !byte 190
; index 35: B5; low byte of the tuning word.
    !byte 76
; index 36: C6; low byte of the tuning word.
    !byte 15

; ntsc_hi: 37 high bytes in chromatic order, C3 through C6.
ntsc_hi:
; index  0: C3; high byte of the tuning word.
    !byte 8
; index  1: C#3; high byte of the tuning word.
    !byte 8
; index  2: D3; high byte of the tuning word.
    !byte 9
; index  3: D#3; high byte of the tuning word.
    !byte 9
; index  4: E3; high byte of the tuning word.
    !byte 10
; index  5: F3; high byte of the tuning word.
    !byte 11
; index  6: F#3; high byte of the tuning word.
    !byte 11
; index  7: G3; high byte of the tuning word.
    !byte 12
; index  8: G#3; high byte of the tuning word.
    !byte 13
; index  9: A3; high byte of the tuning word.
    !byte 14
; index 10: A#3; high byte of the tuning word.
    !byte 14
; index 11: B3; high byte of the tuning word.
    !byte 15
; index 12: C4; high byte of the tuning word.
    !byte 16
; index 13: C#4; high byte of the tuning word.
    !byte 17
; index 14: D4; high byte of the tuning word.
    !byte 18
; index 15: D#4; high byte of the tuning word.
    !byte 19
; index 16: E4; high byte of the tuning word.
    !byte 21
; index 17: F4; high byte of the tuning word.
    !byte 22
; index 18: F#4; high byte of the tuning word.
    !byte 23
; index 19: G4; high byte of the tuning word.
    !byte 25
; index 20: G#4; high byte of the tuning word.
    !byte 26
; index 21: A4; high byte of the tuning word.
    !byte 28
; index 22: A#4; high byte of the tuning word.
    !byte 29
; index 23: B4; high byte of the tuning word.
    !byte 31
; index 24: C5; high byte of the tuning word.
    !byte 33
; index 25: C#5; high byte of the tuning word.
    !byte 35
; index 26: D5; high byte of the tuning word.
    !byte 37
; index 27: D#5; high byte of the tuning word.
    !byte 39
; index 28: E5; high byte of the tuning word.
    !byte 42
; index 29: F5; high byte of the tuning word.
    !byte 44
; index 30: F#5; high byte of the tuning word.
    !byte 47
; index 31: G5; high byte of the tuning word.
    !byte 50
; index 32: G#5; high byte of the tuning word.
    !byte 53
; index 33: A5; high byte of the tuning word.
    !byte 56
; index 34: A#5; high byte of the tuning word.
    !byte 59
; index 35: B5; high byte of the tuning word.
    !byte 63
; index 36: C6; high byte of the tuning word.
    !byte 67

; Low bytes of 3x3 key top-left addresses in colour RAM ($d800 base).
key_lo: !byte 11,109,15,113,19,23,121,27,125,31,129,35,39

; High bytes of those same addresses; keep paired entries in step.
key_hi: !byte 218,217,218,217,218,218,217,218,217,218,217,218,218

; SCREEN TEMPLATE: 25 rows of 40 screen codes, plus 24 padding bytes.
; Codes 1..26 are A..Z; 32 is space. Bit 7 selects reverse video, so
; 160 is a solid reverse-space block and 129 is a reversed A. These are
; screen codes, not the PETSCII character codes used by KERNAL CHROUT.
; Key top-left positions: white row 13 at columns 3,7,11,15,19,23,27,31;
; black row 9 at columns 5,9,17,21,25. All coordinates are zero-based.
screen:
; Screen row 00: Blank top margin.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 01: Centred SID PIANO title.
!byte 32,32,32,32,32,32,32,32,19,32,9,32,4,32,32,32,16,32,9,32,1,32,14,32,15,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 02: Blank separator below title.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 03: Instrument description: THREE VOICES / TRIANGLE.
!byte 32,32,32,32,32,32,32,20,8,18,5,5,32,22,15,9,3,5,19,32,47,32,20,18,9,1,14,7,12,5
    !byte 32,32,32,32,32,32,32,32,32,32
; Screen row 04: OCTAVE RANGE C4 - C5; draw_keys replaces digits at columns 19 and 24.
!byte 32,32,32,32,32,15,3,20,1,22,5,32,18,1,14,7,5,32,3,52,32,45,32,3,53,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32
; Screen row 05: Blank separator before controls.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 06: Number-key octave-control instructions.
!byte 32,32,32,32,49,58,32,15,3,20,1,22,5,32,4,15,23,14,32,32,32,32,50,58,32,15,3,20,1
    !byte 22,5,32,21,16,32,32,32,32,32,32
; Screen row 07: Blank separator above the black keys.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 08: Blank margin above the black-key blocks.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 09: Top solid row of the five accidental-key blocks.
!byte 32,32,32,32,32,160,160,160,32,160,160,160,32,32,32,32,32,160,160,160,32,160,160
    !byte 160,32,160,160,160,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 10: W E T Y U reverse-video labels inside accidental keys.
!byte 32,32,32,32,32,160,151,160,32,160,133,160,32,32,32,32,32,160,148,160,32,160,153
    !byte 160,32,160,149,160,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 11: C# D# F# G# A# reverse-video note labels.
!byte 32,32,32,32,32,160,131,163,32,160,132,163,32,32,32,32,32,160,134,163,32,160,135
    !byte 163,32,160,129,163,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 12: Blank gap between accidental and white-key blocks.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 13: Top solid row of the eight natural-key blocks.
!byte 32,32,32,160,160,160,32,160,160,160,32,160,160,160,32,160,160,160,32,160,160,160
    !byte 32,160,160,160,32,160,160,160,32,160,160,160,32,32,32,32,32,32
; Screen row 14: A S D F G H J K reverse-video labels inside natural keys.
!byte 32,32,32,160,129,160,32,160,147,160,32,160,132,160,32,160,134,160,32,160,135,160
    !byte 32,160,136,160,32,160,138,160,32,160,139,160,32,32,32,32,32,32
; Screen row 15: C D E F G A B C reverse-video note labels.
!byte 32,32,32,160,131,160,32,160,132,160,32,160,133,160,32,160,134,160,32,160,135,160
    !byte 32,160,129,160,32,160,130,160,32,160,131,160,32,32,32,32,32,32
; Screen row 16: Blank separator below the keyboard.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 17: Blank separator before the colour legend.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 18: GREEN: PLAYING / YELLOW: WAITING legend.
!byte 32,32,32,32,7,18,5,5,14,58,32,16,12,1,25,9,14,7,32,32,32,25,5,12,12,15,23,58,32
    !byte 23,1,9,20,9,14,7,32,32,32,32
; Screen row 19: Blank separator before chord instructions.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 20: Instruction to hold up to three notes for chords.
!byte 32,32,32,32,8,15,12,4,32,21,16,32,20,15,32,20,8,18,5,5,32,14,15,20,5,19,32,6,15
    !byte 18,32,3,8,15,18,4,19,32,32,32
; Screen row 21: Blank separator before exit instructions.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 22: RUN/STOP return-to-BASIC instruction.
!byte 32,32,32,32,32,32,32,18,21,14,47,19,20,15,16,58,32,18,5,20,21,18,14,32,20,15,32
    !byte 2,1,19,9,3,32,32,32,32,32,32,32,32
; Screen row 23: Blank lower margin.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 24: Blank final visible row.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    !byte 32,32,32,32,32,32,32,32,32,32,32,32,32
; Screen row 25: 24 non-visible padding bytes for the page-copy loop.
!byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
