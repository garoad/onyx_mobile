# Onyx Editor for iOS

A native iPhone/iPad (SwiftUI + CoreBluetooth) editor for the Pocket AMP running the Onyx custom firmware.
Swift port of the [Onyx Web Editor](https://github.com/28spawn/Pocket-Onyx) (Pocket-Onyx, © 2026 The Onyx Authors, @28spawn), licensed GPL-3.0-only (see `LICENSE`).

Beyond the web editor:
- **Save As**: copy a preset (including unsaved live edits) to any other preset number, with read-back verification.
- **MIDI command reference** in Settings → MIDI Commands, for mapping a foot controller.

Layout: `Packages/OnyxKit` (protocol, model, session, simulator; `swift test`), `OnyxEditor` (SwiftUI app + CoreBluetooth transport).
Run in the Simulator with launch argument `-simulatedUnit` to use a fake unit (no hardware needed).
Not covered: firmware update, flash backup, NAM/cab upload (USB-only in the web editor). Real BLE hardware is untested.
