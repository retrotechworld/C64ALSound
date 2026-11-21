C64 SID complete manuscript with the full piano source

The complete piano listing appears on pages 46 to 70 of the matching manuscript, with a left Comments margin and editable white code on rounded black panels.

Build the piano from this folder:
  acme piano.asm
Load piano.prg into VICE and RUN, or use SYS 2061.
The !to directive sets the output filename, so no additional -o is required.

The six numbered lessons and common.asm are preserved under source/. Their existing VS Code tasks are retained in .vscode/tasks.json.

Verification on 19 November 2026: the original piano source and the manuscript-formatted source both assembled successfully with ACME and produced identical PRG bytes. The formatted source changes comment placement and splits long byte-data directives to fit the page. Every routine, frequency-table entry and screen-data byte is retained. No new VICE listening, physical-keyboard or real-hardware test was performed.

The rest of the latest full SID manuscript, including the foreword, teaching chapters, original source listings, piano case study, figures, references, glossary and index, is preserved. The contents and index include the full piano source listing.
