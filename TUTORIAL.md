# Polyphonic SID keyboard case study

Read the final case study in C64_SID_Complete_Tutorial.docx or .pdf for the illustrated What, Why and How explanation.

## Controls

A W S E D F T G Y H U J K play thirteen chromatic notes C through C. The initial range is C4 to C5. Press 1 for the next lower octave window or 2 for the next higher window, bounded to C3-C4 and C5-C6. Up to three notes can own SID voices. Green means assigned, yellow means held and waiting, and white means released. RUN/STOP returns to BASIC.

## Build and run

piano.asm is self-contained and contains !to "piano.prg", cbm. Start ACME directly with piano.asm as its single argument, using this folder as the working directory. Do not supply an extra output filename. Load piano.prg and RUN; its entry is SYS 2061 ($080D).

The default VS Code build task performs this direct ACME build and automatically launches VICE. Set executable paths in .vscode/tasks.json if needed. The six numbered examples have separate tasks and enter at SYS 4096.

The keyboard scan owns CIA1 and masks IRQs while running. The notes sound as sustained triangle-wave synthesis, not an acoustic piano model. Keyboard ghosting can restrict some combinations. The program restores selected hardware settings on exit; it is a standalone instrument rather than a drop-in background music driver.

Repository: https://github.com/retrotechworld/C64ALSound
