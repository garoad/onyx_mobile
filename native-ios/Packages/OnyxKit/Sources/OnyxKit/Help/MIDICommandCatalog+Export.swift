// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

extension MIDICommandCatalog {
    // MARK: - search

    /// The commands matching every whitespace-separated word of `query` (case-insensitive). A word matches the title, summary, label,
    /// group or notes; a word of digits also matches a CC / program / NRPN number exactly, and a number-only query lists exact
    /// number matches first, CC rows before the rest ("21" finds CC 21 before PC 21 and the text hits). An empty query returns everything.
    public static func filter(_ query: String, in commands: [MIDICommand] = MIDICommandCatalog.all) -> [MIDICommand] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return commands }
        var hits: [(Int, MIDICommand)] = []
        for c in commands {
            let hay = [c.title, c.summary, c.label, c.group.title, c.notes].joined(separator: " ").lowercased()
            var score = 2
            var ok = true
            for w in words {
                if let n = Int(w), c.numbers.contains(n) { score = min(score, c.ccNumber == nil ? 1 : 0) } else if !hay.contains(w) { ok = false; break }
            }
            if ok { hits.append((score, c)) }
        }
        return hits.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map { $0.element.1 }
    }

    public static func search(_ query: String) -> [MIDICommand] { filter(query) }

    // MARK: - plain text

    /// One command as a line: `CC 21 | B0 15 7F | 176 21 127 | Toggle AMP | value >= 64 acts ...`.
    public static func plainText(for command: MIDICommand) -> String {
        [command.label, command.hexString, command.decimalString, command.title, command.valueRule].joined(separator: " | ")
    }

    /// A group as an aligned table with its heading. The 80 Program Changes are folded into one line.
    public static func plainText(for group: MIDICommandGroup) -> String {
        let rows = commands(in: group)
        var lines: [[String]] = []
        if group == .presets {
            lines.append(["PC 0..79", "Cn pp", "192 pp", "Select P01..P80 (pp = preset - 1; n = any channel)", "program 0..79, 80 and above ignored"])
            lines += rows.filter { !$0.message.isProgramChange }.map(columns)
            lines.insert(["PC 12", "C0 0C", "192 12", "example: select P13", ""], at: 1)
        } else {
            lines = rows.map(columns)
        }
        let widths = (0..<5).map { i in lines.map { $0[i].count }.max() ?? 0 }
        let body = lines.map { l in
            zip(l, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }
        return (["== \(group.title) ==", group.intro, ""] + body).joined(separator: "\n")
    }

    private static func columns(_ c: MIDICommand) -> [String] {
        [c.label, c.hexString, c.decimalString, c.title, c.valueRule]
    }

    /// The whole list, ready to paste into a pedal editor or a note.
    public static func plainText() -> String {
        var out = ["Pocket AMP (Onyx) MIDI commands", ""]
        out.append("Channel: any (the unit ignores the channel; examples are on channel 1).")
        out.append("Bluetooth: BLE-MIDI service \(MIDIConnectionFacts.bleServiceUUID), characteristic \(MIDIConnectionFacts.bleCharacteristicUUID).")
        out.append(MIDIConnectionFacts.sysExNote)
        out.append("")
        out.append("Value rules:")
        out += MIDIConnectionFacts.valueRules.map { "  \($0.messages): \($0.rule)" }
        out.append("")
        out.append("Columns: message | bytes (hex) | bytes (decimal) | function | value rule. NRPN rows are the whole CC 99, 98, 6 [, 38] run.")
        for g in groups {
            out.append("")
            out.append(plainText(for: g))
        }
        return out.joined(separator: "\n") + "\n"
    }
}

extension MIDICommand {
    /// Every number a user may type to find this command: CC number, program number, NRPN module and parameter.
    var numbers: Set<Int> {
        switch message {
        case .programChange(let n): return [n]
        case .controlChange(let cc, _): return [cc]
        case .nrpn(let m, let p, _): return [m, p]
        }
    }
}
