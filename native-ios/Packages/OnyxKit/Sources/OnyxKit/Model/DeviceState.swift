// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// One of the eight blocks of the signal chain, in the firmware's slot ids 0...7.
public enum Slot: Int, CaseIterable, Sendable {
    case dyn = 0, drive, amp, cab, eq, mod, dly, rev

    /// The short name the editor shows (`SLOTS` in the web editor).
    public var name: String { ["DYN", "DRIVE", "AMP", "CAB", "EQ", "MOD", "DLY", "REV"][rawValue] }
    /// slot id -> NRPN module number / CC 28+n number (`SLOT_MODULE`).
    public var module: Int { [0, 6, 1, 5, 7, 2, 3, 4][rawValue] }
}

/// The unit's state record (cmd 80, 128 bytes, firmware `pa_sysex.h`), decoded the way the web editor's `decodeState` does.
public struct DeviceState: Equatable, Sendable {
    public struct SlotState: Equatable, Sendable {
        public var on: Bool
        public var type: Int
        /// Six knob values, 0...100 %.
        public var knobs: [Int]
    }

    public struct Globals: Equatable, Sendable {
        public var inGain: Int          // dB, -12...12
        public var gate: Int            // dB, -80 (off) ... -30
        public var outType: Int         // 0 phones, 1 line
        public var cabLine: Int
        public var limiter: Int         // 0 brickwall, 1 soft, 2 off
        public var fizz: Int            // 0...3
        public var width: Int           // 0...100
        public var routing: Int         // 0 stereo, 1 mono, 2 left, 3 right, 4 swap
        public var balance: Int         // -50...50
        public var geq: Int             // global EQ on
        public var bands: [Int]         // five bands, dB -12...12
        public var tunerRef: Int        // Hz, 430...450
        public var tunerMute: Int
        public var loopback: Int
        public var usbMode: Int         // 0 AMP, 1 INTERFACE, 2 INTERFACE + direct monitor
        public var bpm: Int
        public var pattern: Int
        public var gVol: Int
        public var drums: Int
    }

    public var view: Int
    /// Preset index 0...79.
    public var preset: Int
    public var flags: Int
    public var presetVol: Int
    public var outLevel: Int
    public var name: String
    /// Indexed by slot id (`Slot.rawValue`).
    public var slots: [SlotState]
    public var g: Globals
    /// Slot ids for VOL-, VOL+, <, >.
    public var stomp: [Int]
    public var namCount: Int
    public var userCab: Bool
    public var cabCount: Int
    public var namFree: Int
    public var cabFree: Int
    /// Slot ids in signal order.
    public var order: [Int]

    public var isStompMode: Bool { flags & 1 != 0 }
    public var tunerOpen: Bool { flags & 2 != 0 }
    public var groovePlaying: Bool { flags & 4 != 0 }

    /// `decodeState` of the web editor. Returns nil for a record that is too short or not version 1.
    public static func decode(_ r: [UInt8]) -> DeviceState? {
        guard r.count >= 117, r[0] == 1 else { return nil }
        let i = { (n: Int) -> Int in Int(r[n]) }
        var slots: [SlotState] = []
        for s in 0..<8 {
            let o = 22 + s * 8
            slots.append(SlotState(on: r[o] != 0, type: i(o + 1), knobs: (0..<6).map { i(o + 2 + $0) }))
        }
        let g = Globals(
            inGain: i(86) - 12, gate: i(87) - 80, outType: i(88), cabLine: i(89), limiter: i(90), fizz: i(91),
            width: i(92), routing: i(93), balance: i(94) - 50, geq: i(95), bands: (96...100).map { i($0) - 12 },
            tunerRef: i(101) + 430, tunerMute: i(102), loopback: (i(3) >> 3) & 1, usbMode: (i(3) >> 5) & 3,
            bpm: i(106) | (i(107) << 8), pattern: i(108), gVol: i(109), drums: i(110))
        // The name: the non-zero bytes of 6..<22 as Latin-1 characters, trimmed like JS `trim()` (TAB..CR, space, NBSP; not U+0085, unlike Foundation).
        let isBlank = { (b: UInt8) in (9...13).contains(b) || b == 0x20 || b == 0xA0 }
        let nameBytes = Array(r[6..<22].filter { $0 != 0 })
        let trimmed = nameBytes.drop(while: isBlank).reversed().drop(while: isBlank).reversed()
        let name = String(String.UnicodeScalarView(trimmed.map { Unicode.Scalar($0) }))
        var order = [0, 1, 2, 3, 4, 5, 6, 7]
        if r.count >= 125 {
            let o = (117..<125).map { i($0) }
            if Set(o) == Set(0..<8) { order = o }
        }
        return DeviceState(
            view: i(1), preset: i(2), flags: i(3), presetVol: i(4), outLevel: i(5), name: name, slots: slots, g: g,
            stomp: [i(111), i(112), i(113), i(114)], namCount: i(115), userCab: r[116] != 0,
            cabCount: r.count > 125 ? i(125) : 0, namFree: r.count > 126 ? i(126) : 0, cabFree: r.count > 127 ? i(127) : 0,
            order: order)
    }
}
