# Working agreement (all contributors / agents)

* The product: **Onyx Editor for iOS**, a SwiftUI + CoreBluetooth port of `reference/Onyx_Web_Editor.html`
  (Pocket-Onyx by @28spawn, GPL-3.0-only). The HTML is the **authoritative specification**; where it is silent
  see `reference/MIDI-MAP-CUSTOM.md`. Universal app (iPhone + iPad), iOS 17+, Swift 5 language mode.
* `Packages/OnyxKit` is pure Swift (Foundation only, builds and tests on macOS with `swift test`). No SwiftUI,
  no CoreBluetooth in it. The app target `OnyxEditor/` is a synchronized folder: every file under it is compiled.
* Parity is proven by **golden vectors**: `Tools/golden/editor.cjs` loads the ORIGINAL JavaScript (`loadEditor()`),
  a generator `Tools/golden/gen_<area>.cjs` runs it on fixed + seeded-random inputs and writes
  `Packages/OnyxKit/Tests/OnyxKitTests/Fixtures/<area>.json`; Swift tests load the fixture (`Fixtures.load`) and assert
  identical output. Re-run the generator with `node Tools/golden/gen_<area>.cjs`.
* Every Swift file starts with `// SPDX-License-Identifier: GPL-3.0-only`.
* Code style: match the surrounding code, short comments only where the reason is not obvious, no dead code.
* Isolation: develop in a scratch copy (`rsync -a --exclude .build --exclude .git <repo>/ /tmp/onyxw/<id>/`), build and test
  there, then copy ONLY the files you own back into the repo. Never edit a file you do not own; if you need a change
  in someone else's file, say so in your report.
