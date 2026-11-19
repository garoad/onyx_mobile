// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// Channel messages the unit understands (reference/MIDI-MAP-CUSTOM.md). The unit listens on every channel; the editor sends on channel 1.
public enum MIDIControl {
    public static func pc(_ n: Int) -> [UInt8] { [0xC0, UInt8(n & 0x7F)] }

    public static func cc(_ c: Int, _ v: Int) -> [UInt8] { [0xB0, UInt8(c & 0x7F), UInt8(v & 0x7F)] }

    /// An NRPN write (`nrpn`). Modules 0...7: `d` is a percent; modules 8...10 (`raw`): `d` is the raw number (CC 6 alone below 128, else CC 6 + CC 38).
    public static func nrpn(module: Int, param: Int, _ d: Int, raw: Bool = false) -> [UInt8] {
        var out = cc(99, module) + cc(98, param)
        if raw {
            if d < 128 { out += cc(6, d) } else { out += cc(6, d >> 7) + cc(38, d & 127) }
        } else {
            let v = Int((Double(max(0, min(100, d))) * 16383 / 100).rounded())
            out += cc(6, v >> 7) + cc(38, v & 127)
        }
        return out
    }

    /// The unit's own chain move (`chainMove`): the slot goes to position `to`, the ones in between shift by one.
    public static func chainMove(_ order: [Int], slot: Int, to: Int) -> [Int] {
        var o = order
        guard let from = o.firstIndex(of: slot), to >= 0, to <= 7, from != to else { return o }
        o.remove(at: from)
        o.insert(slot, at: min(to, o.count))              // JS `splice` clamps an index past the end
        return o
    }

    /// NRPN module 10 parameter 7: `D = slot * 8 + position`.
    public static func chainMoveMessage(slot: Int, to: Int) -> [UInt8] { nrpn(module: 10, param: 7, slot * 8 + to, raw: true) }

    /// CC value rule: a value >= 64 acts.
    public static let on = 127
    public static let off = 0
}
