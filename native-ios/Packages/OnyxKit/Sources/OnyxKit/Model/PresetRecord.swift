// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The unit's own preset record (`pa_preset_t`, 164 bytes, little endian), the one `presetToRecord` / `recordToPreset` of the web editor read and write.
public struct PresetRecord: Equatable, Sendable {
    public static let size = 164
    public static let magic: UInt32 = 0x32504D50          // "PMP2"
    public static let count = 80
    /// The name field is 24 bytes; the editor writes at most 23 characters so it stays NUL terminated.
    public static let maxNameLength = 23
    public static let flagEmpty: UInt8 = 1

    public var seq: UInt32
    public var name: String
    public var bpm: UInt16
    public var genre: UInt8
    public var customCabIdx: UInt8
    public var customCabBlend: UInt8
    public var inputTrimDb: Int8
    public var gateThresholdPct: UInt8
    /// Bit n = slot id n is on.
    public var slotEnableMask: UInt8
    /// Slot ids in signal order (8).
    public var slotOrder: [UInt8]
    public var ampModel: UInt8
    public var cabModel: UInt8
    public var presetVol: UInt8
    public var flags: UInt8
    /// Type per slot id (8).
    public var slotType: [UInt8]
    /// Slot ids for VOL-, VOL+, <, > (4).
    public var stompMap: [UInt8]
    /// Q16 knob values (0...65535 = 0...100 %): 8 slots x 6.
    public var params: [[UInt16]]

    public var isEmpty: Bool {
        get { flags & Self.flagEmpty != 0 }
        set { flags = newValue ? flags | Self.flagEmpty : flags & ~Self.flagEmpty }
    }

    public init(seq: UInt32, name: String, bpm: UInt16, genre: UInt8, customCabIdx: UInt8, customCabBlend: UInt8, inputTrimDb: Int8,
                gateThresholdPct: UInt8, slotEnableMask: UInt8, slotOrder: [UInt8], ampModel: UInt8, cabModel: UInt8, presetVol: UInt8,
                flags: UInt8, slotType: [UInt8], stompMap: [UInt8], params: [[UInt16]]) {
        self.seq = seq; self.name = name; self.bpm = bpm; self.genre = genre; self.customCabIdx = customCabIdx
        self.customCabBlend = customCabBlend; self.inputTrimDb = inputTrimDb; self.gateThresholdPct = gateThresholdPct
        self.slotEnableMask = slotEnableMask; self.slotOrder = slotOrder; self.ampModel = ampModel; self.cabModel = cabModel
        self.presetVol = presetVol; self.flags = flags; self.slotType = slotType; self.stompMap = stompMap; self.params = params
    }

    // MARK: CRC and validity

    /// CRC-32 (IEEE), as the firmware's `pa_crc32` and the editor's `crc32`.
    public static func crc32(_ b: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for x in b {
            c ^= UInt32(x)
            for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) }
        }
        return ~c
    }

    public static func crc32(_ b: [UInt8]) -> UInt32 { crc32(b[...]) }

    /// `recordOk`: 164 bytes, the magic and a matching CRC.
    public static func isValid(_ r: [UInt8]) -> Bool {
        guard r.count == size else { return false }
        return u32(r, 0) == magic && u32(r, 160) == crc32(r[0..<160])
    }

    // MARK: Encode / decode

    /// `presetToRecord`. Characters are written as their low byte (`charCodeAt & 0xFF`), at most `maxNameLength` of them.
    public func encode() -> [UInt8] {
        var r = [UInt8](repeating: 0, count: Self.size)
        Self.put32(&r, 0, Self.magic)
        Self.put32(&r, 4, seq)
        for (i, u) in name.utf16.prefix(Self.maxNameLength).enumerated() { r[8 + i] = UInt8(truncatingIfNeeded: u) }
        Self.put16(&r, 32, bpm)
        r[34] = genre; r[35] = customCabIdx; r[36] = customCabBlend; r[37] = UInt8(bitPattern: inputTrimDb)
        r[38] = gateThresholdPct; r[39] = slotEnableMask
        for i in 0..<8 { r[40 + i] = slotOrder[i] }
        r[48] = ampModel; r[49] = cabModel; r[50] = presetVol; r[51] = flags
        for i in 0..<8 { r[52 + i] = slotType[i] }
        for i in 0..<4 { r[60 + i] = stompMap[i] }
        for s in 0..<8 { for k in 0..<6 { Self.put16(&r, 64 + 2 * (s * 6 + k), params[s][k]) } }
        Self.put32(&r, 160, Self.crc32(r[0..<160]))
        return r
    }

    /// `recordToPreset`, for a record that passes `isValid`; nil otherwise.
    public init?(record r: [UInt8]) {
        guard Self.isValid(r) else { return nil }
        var end = 8
        while end < 32, r[end] != 0 { end += 1 }
        self.init(
            seq: Self.u32(r, 4),
            name: String(String.UnicodeScalarView(r[8..<end].map { Unicode.Scalar($0) })),
            bpm: UInt16(r[32]) | UInt16(r[33]) << 8, genre: r[34], customCabIdx: r[35], customCabBlend: r[36],
            inputTrimDb: Int8(bitPattern: r[37]), gateThresholdPct: r[38], slotEnableMask: r[39], slotOrder: Array(r[40..<48]),
            ampModel: r[48], cabModel: r[49], presetVol: r[50], flags: r[51], slotType: Array(r[52..<60]), stompMap: Array(r[60..<64]),
            params: (0..<8).map { s in (0..<6).map { k in UInt16(r[64 + 2 * (s * 6 + k)]) | UInt16(r[65 + 2 * (s * 6 + k)]) << 8 } })
    }

    // MARK: Q16 <-> percent

    /// Firmware `pct16`: a percent 0...100 -> Q16.
    public static func q16(percent p: Int) -> UInt16 { UInt16((UInt32(max(0, min(100, p))) * 65535 + 50) / 100) }

    /// The editor's `params_pct`: Q16 -> percent, rounded.
    public static func percent(q16 v: UInt16) -> Int { Int((Double(v) * 100 / 65535).rounded()) }

    // MARK: Little endian helpers

    static func u32(_ r: [UInt8], _ o: Int) -> UInt32 { UInt32(r[o]) | UInt32(r[o + 1]) << 8 | UInt32(r[o + 2]) << 16 | UInt32(r[o + 3]) << 24 }
    static func put32(_ r: inout [UInt8], _ o: Int, _ v: UInt32) { for i in 0..<4 { r[o + i] = UInt8(truncatingIfNeeded: v >> (8 * UInt32(i))) } }
    static func put16(_ r: inout [UInt8], _ o: Int, _ v: UInt16) { r[o] = UInt8(truncatingIfNeeded: v); r[o + 1] = UInt8(truncatingIfNeeded: v >> 8) }
}
