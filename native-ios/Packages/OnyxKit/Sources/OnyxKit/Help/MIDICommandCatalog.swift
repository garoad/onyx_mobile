// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// How the value byte of a command is read by the unit (firmware `usb_ble.c`, `handle_midi_cc`).
public enum ValueHint: Hashable, Sendable {
    /// No value byte (Program Change).
    case none
    /// A button: a value >= 64 acts, a value < 64 is ignored.
    case button
    /// A set: a value >= 64 switches on, a value < 64 switches off.
    case onOff
    /// A continuous CC: every value acts, 0...127 maps to 0...100 %.
    case continuous
    /// NRPN data entry for an effect knob: CC 6 (high 7 bits) and optionally CC 38 (low 7 bits), 14 bit -> 0...100 %.
    case nrpnPercent
    /// NRPN module type (parameter 0x40): CC 6 = 0x20 + the firmware's type id.
    case nrpnType
    /// NRPN module enable (parameter 0x41): CC 6 >= 64 on.
    case nrpnOnOff
    /// NRPN modules 8...10: the raw number D (CC 6 alone below 128, else CC 6 = D >> 7 and CC 38 = D & 127).
    case nrpnRaw(range: ClosedRange<Int>, encoding: String)

    public var rule: String {
        switch self {
        case .none: return "no value byte"
        case .button: return "value >= 64 acts, below 64 is ignored"
        case .onOff: return "value >= 64 on, below 64 off"
        case .continuous: return "any value, 0..127 -> 0..100 %"
        case .nrpnPercent: return "CC 6 (+ CC 38) 14 bit -> 0..100 %"
        case .nrpnType: return "CC 6 = 0x20 + type id"
        case .nrpnOnOff: return "CC 6 >= 64 on, below 64 off"
        case .nrpnRaw(let range, let encoding):
            return "raw D \(range.lowerBound)..\(range.upperBound)" + (encoding.isEmpty ? "" : ", \(encoding)")
        }
    }
}

public enum MIDIMessageKind: Hashable, Sendable {
    case programChange(Int)
    case controlChange(cc: Int, valueHint: ValueHint)
    case nrpn(module: Int, param: Int, valueHint: ValueHint)
}

public enum MIDICommandStatus: Hashable, Sendable {
    case implemented
    /// Documented by the map but the firmware does nothing with it yet.
    case notImplemented
    /// Accepted by the unit but the block has no such control (e.g. knob 5 of the CAB): no effect.
    case noEffect
}

public enum MIDICommandGroup: Int, CaseIterable, Identifiable, Sendable {
    case presets, effectToggle, effectSet, knobs, volumeTunerGroove, frontPanel
    case nrpnModules, nrpnGlobal, nrpnGroove, nrpnPreset

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .presets: return "Presets"
        case .effectToggle: return "Effect on/off (toggle)"
        case .effectSet: return "Effect on/off (set)"
        case .knobs: return "Knobs (direct CC)"
        case .volumeTunerGroove: return "Volume, tuner & groove"
        case .frontPanel: return "Front-panel buttons"
        case .nrpnModules: return "NRPN: effect modules 0..7"
        case .nrpnGlobal: return "NRPN: GLOBAL (module 8)"
        case .nrpnGroove: return "NRPN: GROOVE (module 9)"
        case .nrpnPreset: return "NRPN: PRESET (module 10)"
        }
    }

    public var intro: String {
        switch self {
        case .presets: return "Program Change selects a preset; CC 80/81 step through them; CC 88 saves the current sound."
        case .effectToggle: return "One press flips the block. The pedal does not know the unit's state, so it can get out of step: see the set variants."
        case .effectSet: return "Value >= 64 switches the block on, below 64 off. Use these with a latching switch so the pedal LED stays in sync."
        case .knobs: return "17 knobs on plain CC numbers, ideal for an expression pedal: 0..127 spans 0..100 %."
        case .volumeTunerGroove: return "Preset volume, tuner, Groove Station play/stop and the STOMP/PRESET play mode."
        case .frontPanel: return "These press the unit's own buttons. Value >= 64 acts."
        case .nrpnModules: return "Every knob, model and on/off of the eight effect blocks. Send CC 99 (module), CC 98 (parameter), then CC 6 (+ CC 38)."
        case .nrpnGlobal: return "The unit's general settings. The value is a raw number D, not a percentage."
        case .nrpnGroove: return "Groove Station settings. The value is a raw number D."
        case .nrpnPreset: return "Preset volume, the STOMP key map and the chain move. The value is a raw number D."
        }
    }
}

public struct MIDICommand: Identifiable, Hashable, Sendable {
    public let id: String
    public let group: MIDICommandGroup
    public let title: String
    public let summary: String
    public let message: MIDIMessageKind
    /// A ready-to-copy byte sequence on channel 1 with a concrete value (an NRPN is the whole CC 99 / 98 / 6 [/ 38] run).
    public let example: [UInt8]
    public let notes: String
    public let status: MIDICommandStatus

    public init(id: String, group: MIDICommandGroup, title: String, summary: String, message: MIDIMessageKind,
                example: [UInt8], notes: String = "", status: MIDICommandStatus = .implemented) {
        self.id = id; self.group = group; self.title = title; self.summary = summary
        self.message = message; self.example = example; self.notes = notes; self.status = status
    }

    /// "PC 12", "CC 21", "NRPN 1/0".
    public var label: String {
        switch message {
        case .programChange(let n): return "PC \(n)"
        case .controlChange(let cc, _): return "CC \(cc)"
        case .nrpn(let m, let p, _): return "NRPN \(m)/\(p)" + (p >= 0x40 ? String(format: " (0x%02X)", p) : "")
        }
    }

    public var ccNumber: Int? {
        if case .controlChange(let cc, _) = message { return cc }
        return nil
    }

    public var programNumber: Int? {
        if case .programChange(let n) = message { return n }
        return nil
    }

    public var valueHint: ValueHint {
        switch message {
        case .programChange: return .none
        case .controlChange(_, let h), .nrpn(_, _, let h): return h
        }
    }

    public var valueRule: String {
        let r = message.isProgramChange ? "program 0..79, 80 and above ignored" : valueHint.rule
        switch status {
        case .implemented: return r
        case .notImplemented: return "NOT IMPLEMENTED in the firmware (" + r + ")"
        case .noEffect: return "accepted, no effect (this block has no such knob)"
        }
    }

    /// "B0 15 7F"
    public var hexString: String { example.map { String(format: "%02X", $0) }.joined(separator: " ") }
    /// "176 21 127"
    public var decimalString: String { example.map(String.init).joined(separator: " ") }
}

extension MIDIMessageKind {
    var isProgramChange: Bool {
        if case .programChange = self { return true }
        return false
    }
}

/// Every command the unit accepts over MIDI, taken from reference/MIDI-MAP-CUSTOM.md sections 1b / 2 / 6 and checked against
/// the firmware's handler (usb_ble.c `handle_midi_cc`) and its test (test_midi_control.py). The firmware wins over the map.
///
/// Left out on purpose: CC 90...94. They are BENCH-ONLY switches that retime the unit's USB audio service (`pa_usb_dev_set_service_mode` /
/// `set_timer_prio`); a pedal that sends one by accident would disturb the USB audio, and they are not part of the map's controls.
/// CC 119 is reserved and not handled. CC 6 / 38 / 98 / 99 / 100 / 101 are the NRPN plumbing, listed in `nrpnPlumbingCCs`.
public enum MIDICommandCatalog {
    public static let all: [MIDICommand] = build()
    public static let groups: [MIDICommandGroup] = MIDICommandGroup.allCases

    /// The CC numbers every NRPN run is made of: 99 module, 98 parameter, 6 data high, 38 data low, 101/100 = 127 (RPN null) clears the selection.
    public static let nrpnPlumbingCCs = [6, 38, 98, 99, 100, 101]
    /// Reserved by the map, not handled by the firmware.
    public static let reservedCCs = [119]

    public static func commands(in group: MIDICommandGroup) -> [MIDICommand] { all.filter { $0.group == group } }
    public static func command(id: String) -> MIDICommand? { all.first { $0.id == id } }

    // MARK: - building

    /// Slot of the NRPN module / CC 28+n number.
    private static func slot(ofModule n: Int) -> Slot { Slot.allCases.first { $0.module == n }! }

    /// The name a pedal editor user knows: the stock map calls module 0 "FX".
    static func moduleName(_ n: Int) -> String { n == 0 ? "FX (DYN)" : slot(ofModule: n).name }

    private static func pcRow(_ n: Int) -> MIDICommand {
        let name = "P" + String(format: "%02d", n + 1)
        return MIDICommand(
            id: "pc.\(n)", group: .presets, title: "Select \(name)",
            summary: "Program Change \(n) selects preset \(name) (bank \(n / 4 + 1), slot \(["A", "B", "C", "D"][n % 4])).",
            message: .programChange(n), example: MIDIControl.pc(n),
            notes: "Program 0..79 only; 80..127 are ignored. Bank = n / 4 + 1, slot A..D = n % 4.")
    }

    private static func ccRow(_ cc: Int, _ group: MIDICommandGroup, _ title: String, _ summary: String, _ hint: ValueHint,
                              value: Int, notes: String = "") -> MIDICommand {
        MIDICommand(id: "cc.\(cc)", group: group, title: title, summary: summary,
                    message: .controlChange(cc: cc, valueHint: hint), example: MIDIControl.cc(cc, value), notes: notes)
    }

    /// Knob labels per model, from the web editor's TABLES.params ("---" = no control). The index is the model number.
    static let knobTables: [Slot: [[String]]] = [
        .dyn: [["THRESH", "RELEASE", "ATTACK", "LEVEL"], ["THRESH", "RELEASE", "---", "BOOST"], ["THRESH", "RATIO", "ATTACK", "LEVEL"],
               ["THRESH", "RELEASE", "ATTACK", "LEVEL"], ["THRESH", "RATIO", "ATTACK", "LEVEL"]],
        .drive: [["DRIVE", "TONE", "LEVEL"]],
        .amp: [["GAIN", "BASS", "MID", "TREBLE", "PRES", "MASTER"]],
        .cab: [["LEVEL", "LOWCUT", "HICUT"]],
        .eq: [["100", "400", "1k", "3k", "8k"], ["LOWCUT", "HICUT", "LEVEL"], ["LOW", "MID", "FREQ", "HIGH"]],
        .mod: [["RATE", "DEPTH", "MIX", "---"], ["RATE", "DEPTH", "MIX", "FDBK"], ["RATE", "DEPTH", "MIX", "FDBK"], ["RATE", "DEPTH", "---", "---"],
               ["RATE", "DEPTH", "---", "---"], ["RATE", "RANGE", "MIX", "RESO"], ["FALL", "SENS", "MIX", "RESO"]],
        .dly: ["MOD", "RELEASE", "GRIT", "RATIO", "GRIT", "TONE", "TONE", "TONE", "TONE"].map { ["TIME", "FDBK", "MIX", $0] },
        .rev: [["DECAY", "LOWCUT", "TONE", "MIX"]],
    ]

    /// Model names per block (TABLES.models). AMP and CAB are not listed: their models are the unit's own list (stock + user captures).
    static let modelNames: [Slot: [String]] = [
        .dyn: ["GATE", "BOOST+GATE", "COMP+GATE", "AI GATE MS", "COMP"],
        .drive: ["TS-808", "KLON", "OCD", "RAT", "BIG MUFF", "FUZZ FACE"],
        .eq: ["5-BAND", "LOW/HIGH CUT", "PARAMETRIC-3"],
        .mod: ["CHORUS", "PHASER", "FLANGER", "TREMOLO", "VIBRATO", "WAH", "AUTO WAH"],
        .dly: ["ANALOG", "DUCKING", "TAPE", "DUAL", "LO-FI", "DIGITAL", "PING PONG", "REVERSE", "SLAPBACK"],
        .rev: ["ROOM", "HALL", "SWELL", "SPRING", "SHIMMER", "CLOUD", "PLATE"],
    ]

    /// Distinct labels of knob `k` over all models of the block, in model order. Empty: the block has no such knob.
    static func knobLabels(_ slot: Slot, knob k: Int) -> [String] {
        var out: [String] = []
        for labels in knobTables[slot] ?? [] where k < labels.count && labels[k] != "---" && !out.contains(labels[k]) { out.append(labels[k]) }
        return out
    }

    private static func nrpnRow(module: Int, param: Int, _ title: String, _ summary: String, _ hint: ValueHint, group: MIDICommandGroup,
                                d: Int, raw: Bool, notes: String = "", status: MIDICommandStatus = .implemented) -> MIDICommand {
        MIDICommand(id: "nrpn.\(module).\(param)", group: group, title: title, summary: summary,
                    message: .nrpn(module: module, param: param, valueHint: hint),
                    example: MIDIControl.nrpn(module: module, param: param, d, raw: raw), notes: notes, status: status)
    }

    private static func build() -> [MIDICommand] {
        var rows: [MIDICommand] = []

        // Presets
        rows += (0..<80).map(pcRow)
        rows.append(ccRow(80, .presets, "Next preset", "Steps to the next preset; P80 wraps to P01.", .button, value: 127))
        rows.append(ccRow(81, .presets, "Previous preset", "Steps to the previous preset; P01 wraps to P80.", .button, value: 127))
        rows.append(ccRow(88, .presets, "Save current sound", "Stores the current sound, including knobs changed over MIDI, in the current preset (the editor's save button).",
                          .button, value: 127, notes: "Needs a value >= 64; a lower value does nothing."))

        // Effect on/off
        for n in 0..<8 {
            rows.append(ccRow(20 + n, .effectToggle, "Toggle \(moduleName(n))", "Flips the \(moduleName(n)) block on/off on every press.", .button, value: 127,
                              notes: n < 6 ? "Stock map compatible (CC 20..25 in the stock module order FX, AMP, MOD, DLY, REV, CAB)." : "Added by Onyx (new DRIVE / EQ blocks)."))
        }
        for n in 0..<8 {
            rows.append(ccRow(28 + n, .effectSet, "Set \(moduleName(n)) on/off", "Value >= 64 switches \(moduleName(n)) on, below 64 off.", .onOff, value: 127,
                              notes: "Not a toggle: sending the same value twice leaves the block unchanged, so the pedal LED cannot drift."))
        }

        // Knobs, CC 102...118: (name, NRPN module, native knob), from the firmware's k_cc_knob.
        let knobs: [(String, Int, Int)] = [
            ("AMP Gain", 1, 0), ("AMP Level (master)", 1, 5), ("AMP Bass", 1, 1), ("AMP Mid", 1, 2), ("AMP Treble", 1, 3), ("AMP Presence", 1, 4),
            ("DRIVE Drive", 6, 0), ("DLY Time", 3, 0), ("DLY Feedback", 3, 1), ("DLY Mix", 3, 2), ("REV Decay", 4, 0), ("REV Mix", 4, 3),
            ("MOD Speed", 2, 0), ("MOD Depth", 2, 1), ("CAB Level", 5, 0), ("CAB Low Cut", 5, 1), ("CAB High Cut", 5, 2),
        ]
        for (i, k) in knobs.enumerated() {
            rows.append(ccRow(102 + i, .knobs, k.0, "Sets \(k.0) directly, 0..127 -> 0..100 %.", .continuous, value: 64,
                              notes: "Same knob as NRPN \(k.1)/\(k.2). Acts at every value; works for whatever model the block has loaded."))
        }

        // Volume, tuner, groove, play mode
        rows.append(ccRow(7, .volumeTunerGroove, "Preset volume", "Sets the preset volume, 0..127 -> 0..100 % (the VOL bar).", .continuous, value: 100,
                          notes: "Same as NRPN 10/0."))
        rows.append(ccRow(85, .volumeTunerGroove, "Tuner on/off", "Value >= 64 opens the tuner, below 64 closes it.", .onOff, value: 127))
        rows.append(ccRow(86, .volumeTunerGroove, "Groove play/stop", "Value >= 64 starts the Groove Station, below 64 stops it.", .onOff, value: 127))
        rows.append(ccRow(87, .volumeTunerGroove, "Play mode", "Value >= 64 selects STOMP mode, below 64 PRESET mode.", .onOff, value: 127))

        // Front-panel buttons
        for (cc, name, what) in [(64, "HOME", "the HOME button"), (65, "PARA click", "a click on the PARA knob"),
                                 (66, "PARA CCW", "one step counter-clockwise on the PARA knob"), (67, "PARA CW", "one step clockwise on the PARA knob")] {
            rows.append(ccRow(cc, .frontPanel, name, "Presses \(what).", .button, value: 127))
        }

        // NRPN effect modules
        for n in 0..<8 {
            let s = slot(ofModule: n), name = s.name
            let models = modelNames[s].map { m in m.enumerated().map { "0x" + String(0x20 + $0.offset, radix: 16, uppercase: true) + " " + $0.element }.joined(separator: ", ") }
            rows.append(nrpnRow(module: n, param: 0x41, "\(name) on/off", "Switches the \(moduleName(n)) block on (CC 6 >= 64) or off.", .nrpnOnOff,
                                group: .nrpnModules, d: 127, raw: true, notes: "Same as CC \(28 + n)."))
            rows.append(nrpnRow(module: n, param: 0x40, "\(name) model", "Selects the \(name) model: CC 6 = 0x20 + the model number.", .nrpnType,
                                group: .nrpnModules, d: 0x21, raw: true,
                                notes: (models.map { "Models: \($0). " } ?? "Model numbers are the unit's own list in the editor's picker (stock models first, then user captures). ")
                                    + "A value below 0x20 is also taken as the model number; a number the block does not have is ignored."))
            let count = knobTables[s]!.map(\.count).max()!
            for native in [false, true] {
                for k in 0..<6 {
                    let param = (native ? 0x60 : 0) + k
                    let labels = knobLabels(s, knob: k)
                    let kind = native ? "native knob" : "knob"
                    if k >= count {
                        rows.append(nrpnRow(module: n, param: param, "\(name) \(kind) \(k) (unused)", "The \(name) block has no \(kind) \(k).", .nrpnPercent,
                                            group: .nrpnModules, d: 50, raw: false,
                                            notes: "The unit accepts and ignores it.", status: .noEffect))
                    } else {
                        rows.append(nrpnRow(module: n, param: param, "\(name) \(labels.joined(separator: " / ")) (\(kind) \(k))",
                                            "Sets \(kind) \(k) of \(name), 0..100 % in 14 bit. Control: \(labels.joined(separator: " / ")) depending on the model.",
                                            .nrpnPercent, group: .nrpnModules, d: 50, raw: false,
                                            notes: native ? "Same knob as NRPN \(n)/\(k)." :
                                                "Firmware-native knob \(k): the stock-record order is NOT applied. NRPN \(n)/\(0x60 + k) (0x\(String(0x60 + k, radix: 16, uppercase: true))) addresses the same knob."))
                    }
                }
            }
        }

        // NRPN GLOBAL
        for p in GlobalParam.allCases {
            let spec = p.spec
            let range: ClosedRange<Int>, summary: String, d: Int
            switch spec.kind {
            case .slider(let r): range = r
            case .picker(let items): range = 0...(items.count - 1)
            case .toggle: range = 0...1
            }
            var encoding = ""
            switch p {
            case .inputGain: encoding = "D = dB + 12 (-12..+12 dB)"; d = 12
            case .inputGate: encoding = "D = dB + 80 (0 = off, 50 = -30 dB)"; d = 20
            case .outputLevel: encoding = "D = percent"; d = 80
            case .outputType: encoding = "0 phones, 1 line"; d = 1
            case .cabOnLine: encoding = "0 off, 1 on"; d = 1
            case .limiter: encoding = "0 brickwall, 1 soft, 2 off"; d = 1
            case .fizz: encoding = "level 0..3"; d = 2
            case .width: encoding = "D = percent"; d = 50
            case .routing: encoding = "0 stereo, 1 mono, 2 left, 3 right, 4 swap"; d = 0
            case .balance: encoding = "D = balance + 50 (-50..+50)"; d = 50
            case .globalEQ: encoding = "0 off, 1 on"; d = 1
            case .eq100, .eq400, .eq1k, .eq3k, .eq8k: encoding = "D = dB + 12 (-12..+12 dB)"; d = 12
            case .tunerReference: encoding = "D = Hz - 430 (430..450 Hz)"; d = 10
            case .tunerMute: encoding = "0 off, 1 on"; d = 1
            case .usbLoopback: encoding = "0 off, 1 on"; d = 1
            case .usbMode: encoding = "0 AMP, 1 INTERFACE, 2 INTERFACE + direct monitor"; d = 0
            }
            summary = "Sets \(spec.title.lowercased()); \(encoding)."
            rows.append(nrpnRow(module: 8, param: p.rawValue, "Global: \(spec.title)", summary, .nrpnRaw(range: range, encoding: encoding),
                                group: .nrpnGlobal, d: d, raw: true,
                                notes: "Raw number D, not a percentage. A change marks the settings to be saved (about 2 s later); the master knob and a MIDI level follow the last change."))
        }

        // NRPN GROOVE
        let groove: [(Int, String, ClosedRange<Int>, String, Int, String)] = [
            (0, "Groove play", 0...1, "0 stop, 1 play", 1, "Same as CC 86."),
            (1, "Groove BPM", 0...220, "D = BPM - 40 (40..260 BPM)", 80, "Above 127 send CC 6 = D >> 7 then CC 38 = D & 127; the unit first applies the CC 6 alone, then the full value."),
            (2, "Groove pattern", 0...39, "pattern 0..39 (shown as 1..40)", 7, ""),
            (3, "Groove volume", 0...100, "D = percent", 55, ""),
            (4, "Groove drums", 0...1, "0 off, 1 on", 1, ""),
        ]
        for g in groove {
            rows.append(nrpnRow(module: 9, param: g.0, g.1, "Sets \(g.1.lowercased()); \(g.3).", .nrpnRaw(range: g.2, encoding: g.3), group: .nrpnGroove,
                                d: g.4, raw: true, notes: g.5))
        }

        // NRPN PRESET
        rows.append(nrpnRow(module: 10, param: 0, "Preset volume", "Sets the preset volume; D = percent.", .nrpnRaw(range: 0...100, encoding: "D = percent"),
                            group: .nrpnPreset, d: 70, raw: true, notes: "Same as CC 7."))
        rows.append(nrpnRow(module: 10, param: 1, "Preset input trim", "Per-preset input trim, -12..+12 dB.", .nrpnRaw(range: 0...24, encoding: "D = dB + 12"),
                            group: .nrpnPreset, d: 12, raw: true,
                            notes: "The unit stores the value but the DSP does not use it yet.", status: .notImplemented))
        rows.append(nrpnRow(module: 10, param: 2, "Preset gate threshold", "Per-preset gate threshold.", .nrpnRaw(range: 0...100, encoding: "D = percent"),
                            group: .nrpnPreset, d: 50, raw: true,
                            notes: "The unit stores the value but the DSP does not use it yet.", status: .notImplemented))
        for (i, key) in Stomp.keys.enumerated() {
            rows.append(nrpnRow(module: 10, param: 3 + i, "Stomp key \(key)", "Picks the block the STOMP-mode key \(key) controls.",
                                .nrpnRaw(range: 0...7, encoding: "module number: " + Stomp.moduleNames.enumerated().map { "\($0.offset) \($0.element)" }.joined(separator: ", ")),
                                group: .nrpnPreset, d: 1, raw: true, notes: "A number above 7 is ignored."))
        }
        rows.append(nrpnRow(module: 10, param: 7, "Chain move", "Moves a block to a position in the signal chain (the editor's drag and drop).",
                            .nrpnRaw(range: 0...63, encoding: "D = slot * 8 + position"),
                            group: .nrpnPreset, d: 16, raw: true,
                            notes: "Slot id: DYN 0, DRIVE 1, AMP 2, CAB 3, EQ 4, MOD 5, DLY 6, REV 7; position 0..7 in signal order, the others shift. The example moves AMP to the front. Ignored while the unit is in its move mode; not saved until CC 88."))
        return rows
    }
}
