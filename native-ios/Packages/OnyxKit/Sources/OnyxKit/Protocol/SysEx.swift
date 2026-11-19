// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The unit's SysEx framing: `F0 <8->7 bit packed inner frame> F7`, inner = `00 59 cmd len:u24le payload chk`.
public enum SysEx {
    public static let maxPayload = 256

    public struct Reply: Equatable, Sendable {
        public var type: UInt8
        public var data: [UInt8]
    }

    /// 8-bit bytes -> 7-bit bytes, least significant bits first (`pack8to7`).
    public static func pack8to7(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var bits = 0, n = 0
        for b in data {
            bits |= Int(b) << n
            n += 8
            while n >= 7 { out.append(UInt8(bits & 0x7F)); bits >>= 7; n -= 7 }
        }
        if n > 0 { out.append(UInt8(bits & 0x7F)) }
        return out
    }

    /// 7-bit bytes -> 8-bit bytes (`unpack7to8`). A trailing partial byte is dropped.
    public static func unpack7to8(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var bits = 0, n = 0
        for b in data {
            bits |= Int(b & 0x7F) << n
            n += 7
            if n >= 8 { out.append(UInt8(bits & 0xFF)); bits >>= 8; n -= 8 }
        }
        return out
    }

    /// One command frame (`buildFrame`). Throws when the payload is over `maxPayload` bytes.
    public static func buildFrame(cmd: UInt8, payload: [UInt8] = []) throws -> [UInt8] {
        guard payload.count <= maxPayload else { throw OnyxLinkError.protocolError("payload over \(maxPayload) bytes") }
        let l = payload.count
        var inner: [UInt8] = [0x00, 0x59, cmd, UInt8(l & 0xFF), UInt8((l >> 8) & 0xFF), UInt8((l >> 16) & 0xFF)]
        inner += payload
        var s = Int(cmd) + Int(inner[3]) + Int(inner[4]) + Int(inner[5])
        for b in payload { s += Int(b) }
        inner.append(UInt8(truncatingIfNeeded: ~s))
        return [0xF0] + pack8to7(inner) + [0xF7]
    }

    /// A reply frame -> its type and data, or nil when it is not a valid frame (`parseReply`).
    public static func parseReply(_ frame: [UInt8]) -> Reply? {
        guard frame.count >= 2, frame.first == 0xF0, frame.last == 0xF7 else { return nil }
        let inner = unpack7to8(Array(frame[1..<(frame.count - 1)]))
        guard inner.count >= 7, inner[0] == 0, inner[1] == 0x59 else { return nil }
        let len = Int(inner[3]) | (Int(inner[4]) << 8) | (Int(inner[5]) << 16)
        guard inner.count >= 7 + len else { return nil }
        let data = Array(inner[6..<(6 + len)])
        var s = Int(inner[2]) + Int(inner[3]) + Int(inner[4]) + Int(inner[5])
        for b in data { s += Int(b) }
        guard inner[6 + len] == UInt8(truncatingIfNeeded: ~s) else { return nil }
        return Reply(type: inner[2], data: data)
    }
}
