// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// BLE-MIDI 1.0 packet framing (`bleFrames` / `BleUnframer` of the web editor; the unit side is custom-fw/src/board/ble_midi.c).
public enum BLEMIDI {
    public static let serviceUUID = "03B80E5A-EDE8-4B33-A751-6CE34EC4C700"
    public static let characteristicUUID = "7772E5DB-3868-4112-A1A9-F2669D106BF3"

    /// Packets for one MIDI message: `[hdr][ts] F0 data..` / `[hdr] data..` / `.. [ts] F7`.
    /// - Parameters:
    ///   - chunkMax: the largest packet (the web editor uses 20, the BLE minimum payload).
    ///   - timestamp: milliseconds; only the low 13 bits are used.
    public static func frames(_ msg: [UInt8], chunkMax: Int, timestamp: Int) -> [[UInt8]] {
        let ts = timestamp & 0x1FFF
        let hdr = UInt8(0x80 | (ts >> 7)), lo = UInt8(0x80 | (ts & 0x7F))
        guard msg.first == 0xF0 else { return [[hdr, lo] + msg] }
        let body = Array(msg.dropLast())                    // F0 + data; the F7 is added with a timestamp
        var pkts: [[UInt8]] = []
        var i = 0, first = true
        while i < body.count {
            let head: [UInt8] = first ? [hdr, lo] : [hdr]
            let room = chunkMax - head.count - 2            // two bytes stay free for the closing [ts, F7]
            let take = min(room, body.count - i)
            precondition(take > 0, "chunkMax too small for a BLE-MIDI SysEx packet")
            pkts.append(head + body[i..<(i + take)])
            i += take
            first = false
        }
        pkts[pkts.count - 1] += [lo, 0xF7]
        return pkts
    }

    /// Notification payloads from the device -> complete SysEx frames `F0 .. F7` (`BleUnframer`).
    public struct Unframer {
        private var buf: [UInt8] = []
        private var inSysEx = false
        public init() {}

        public mutating func push(_ p: [UInt8]) -> [[UInt8]] {
            var out: [[UInt8]] = []
            guard p.count > 1 else { return out }
            for b in p[1...] {
                if b == 0xF0 { buf = [0xF0]; inSysEx = true }
                else if b == 0xF7 { if inSysEx { buf.append(0xF7); out.append(buf) }; buf = []; inSysEx = false }
                else if b & 0x80 != 0 { /* a timestamp, or a status byte outside SysEx */ }
                else if inSysEx { buf.append(b) }
            }
            return out
        }

        public mutating func reset() { buf = []; inSysEx = false }
    }
}
