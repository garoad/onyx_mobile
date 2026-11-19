// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The preset backup document, format `pocket-amp-presets` version 1: the JSON the web editor and the PC tools (`preset_bank_pc.py`, `abkx_to_json.py`)
/// read and write. Field names are the JSON keys. Reading is as lenient as the editor's (missing numbers are 0, numbers wrap like typed-array stores);
/// `jsonData()` writes what `JSON.stringify(doc, null, 1) + "\n"` writes.
public struct PresetBankDocument: Codable, Equatable, Sendable {
    public static let format = "pocket-amp-presets"
    public static let unitNote = "Onyx preset backup read from the unit. Edit names and values freely; 'params' are Q16 (0..65535 = 0..100 %), 'params_pct' is for reading only. Slot order: DYN DRV AMP CAB EQ MOD DLY REV."
    public static let abkxNote = "Onyx preset backup converted from an 80-slot 92-byte bank. Edit names and values freely; 'params' are Q16 (0..65535 = 0..100 %), 'params_pct' is for reading only. Slot order: DYN DRV AMP CAB EQ MOD DLY REV."

    public var format: String
    public var version: Int
    public var recordSize: Int
    public var note: String
    public var presets: [Item]

    public init(note: String, presets: [Item]) {
        format = Self.format; version = 1; recordSize = PresetRecord.size; self.note = note; self.presets = presets
    }

    private enum CodingKeys: String, CodingKey { case format, version, note, presets, recordSize = "record_size" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        guard format == Self.format else { throw PresetBankFile.FormatError("not a pocket-amp-presets file") }
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        recordSize = (try? c.decode(Int.self, forKey: .recordSize)) ?? PresetRecord.size
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        presets = try c.decode([Item].self, forKey: .presets)
    }

    /// One element of `presets`: a preset or a slot the unit could not deliver.
    public enum Item: Codable, Equatable, Sendable {
        case preset(Entry)
        /// `{ "slot": n, "unreadable": true }`, the 1-based slot number.
        case unreadable(slot: Int)

        public var slot: Int {
            switch self { case .preset(let e): return e.slot; case .unreadable(let s): return s }
        }

        private enum Keys: String, CodingKey { case slot, unreadable }

        public init(from decoder: Decoder) throws {
            if let one = try? decoder.singleValueContainer(), one.decodeNil() { throw PresetBankFile.FormatError("Cannot read properties of null (reading 'unreadable')") }
            // any other element that is not an object is skipped by the editor (its slot reads as 0)
            guard let c = try? decoder.container(keyedBy: Keys.self) else { self = .unreadable(slot: 0); return }
            if Lenient.truthy(c, .unreadable) { self = .unreadable(slot: Lenient.int(c, .slot)) } else { self = .preset(try Entry(from: decoder)) }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .preset(let e): try e.encode(to: encoder)
            case .unreadable(let s):
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(s, forKey: .slot); try c.encode(true, forKey: .unreadable)
            }
        }
    }

    /// One preset, field for field as in the JSON (`recordToPreset`). `params` are Q16 per slot id (8 rows of 6; 48 numbers in any row shape are accepted
    /// on reading), `paramsPct` is for reading only.
    public struct Entry: Codable, Equatable, Sendable {
        public var slot: Int
        public var name: String
        public var empty: Bool
        public var seq: Int
        public var bpm: Int
        public var genre: Int
        public var customCabIdx: Int
        public var customCabBlend: Int
        public var inputTrimDb: Int
        public var gateThresholdPct: Int
        public var slotEnableMask: Int
        public var slotOrder: [Int]
        public var ampModel: Int
        public var cabModel: Int
        public var presetVol: Int
        public var flags: Int
        public var slotType: [Int]
        public var stompMap: [Int]
        public var params: [[Int]]
        public var paramsPct: [[Int]]

        enum CodingKeys: String, CodingKey {
            case slot, name, empty, seq, bpm, genre, flags, params
            case customCabIdx = "custom_cab_idx", customCabBlend = "custom_cab_blend", inputTrimDb = "input_trim_db"
            case gateThresholdPct = "gate_threshold_pct", slotEnableMask = "slot_enable_mask", slotOrder = "slot_order"
            case ampModel = "amp_model", cabModel = "cab_model", presetVol = "preset_vol", slotType = "slot_type"
            case stompMap = "stomp_map", paramsPct = "params_pct"
        }

        public init(slot: Int, name: String, empty: Bool, seq: Int, bpm: Int, genre: Int, customCabIdx: Int, customCabBlend: Int, inputTrimDb: Int,
                    gateThresholdPct: Int, slotEnableMask: Int, slotOrder: [Int], ampModel: Int, cabModel: Int, presetVol: Int, flags: Int,
                    slotType: [Int], stompMap: [Int], params: [[Int]], paramsPct: [[Int]]) {
            self.slot = slot; self.name = name; self.empty = empty; self.seq = seq; self.bpm = bpm; self.genre = genre
            self.customCabIdx = customCabIdx; self.customCabBlend = customCabBlend; self.inputTrimDb = inputTrimDb
            self.gateThresholdPct = gateThresholdPct; self.slotEnableMask = slotEnableMask; self.slotOrder = slotOrder
            self.ampModel = ampModel; self.cabModel = cabModel; self.presetVol = presetVol; self.flags = flags
            self.slotType = slotType; self.stompMap = stompMap; self.params = params; self.paramsPct = paramsPct
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slot = Lenient.int(c, .slot)
            name = Lenient.string(c, .name)
            empty = Lenient.truthy(c, .empty)
            seq = Lenient.int(c, .seq); bpm = Lenient.int(c, .bpm); genre = Lenient.int(c, .genre)
            customCabIdx = Lenient.int(c, .customCabIdx); customCabBlend = Lenient.int(c, .customCabBlend); inputTrimDb = Lenient.int(c, .inputTrimDb)
            gateThresholdPct = Lenient.int(c, .gateThresholdPct); slotEnableMask = Lenient.int(c, .slotEnableMask)
            slotOrder = Lenient.ints(c, .slotOrder)
            ampModel = Lenient.int(c, .ampModel); cabModel = Lenient.int(c, .cabModel); presetVol = Lenient.int(c, .presetVol); flags = Lenient.int(c, .flags)
            slotType = Lenient.ints(c, .slotType); stompMap = Lenient.ints(c, .stompMap)
            params = Lenient.rows(c, .params)
            let pct = Lenient.rows(c, .paramsPct)
            paramsPct = c.contains(.paramsPct) ? pct : params.map { $0.map { PresetRecord.percent(q16: UInt16(truncatingIfNeeded: $0)) } }
        }

        /// `recordToPreset(index, r)` for a record that passes `PresetRecord.isValid`. `index` is the 0-based slot.
        public init(index: Int, record r: [UInt8]) {
            func u16(_ o: Int) -> Int { Int(r[o]) | Int(r[o + 1]) << 8 }
            var end = 8
            while end < 32, r[end] != 0 { end += 1 }
            let q = (0..<48).map { u16(64 + 2 * $0) }
            func rows(_ a: [Int]) -> [[Int]] { (0..<8).map { Array(a[$0 * 6..<$0 * 6 + 6]) } }
            self.init(
                slot: index + 1, name: String(String.UnicodeScalarView(r[8..<end].map { Unicode.Scalar($0) })), empty: r[51] & 1 != 0,
                seq: Int(PresetRecord.u32(r, 4)), bpm: u16(32), genre: Int(r[34]), customCabIdx: Int(r[35]), customCabBlend: Int(r[36]),
                inputTrimDb: Int(Int8(bitPattern: r[37])), gateThresholdPct: Int(r[38]), slotEnableMask: Int(r[39]), slotOrder: r[40..<48].map(Int.init),
                ampModel: Int(r[48]), cabModel: Int(r[49]), presetVol: Int(r[50]), flags: Int(r[51]), slotType: r[52..<60].map(Int.init),
                stompMap: r[60..<64].map(Int.init), params: rows(q), paramsPct: rows(q.map { PresetRecord.percent(q16: UInt16($0)) }))
        }

        public init(index: Int, record: PresetRecord) { self.init(index: index, record: record.encode()) }

        /// `presetToRecord`: the 164-byte record. Throws when the arrays have the wrong length.
        public func recordBytes() throws -> [UInt8] {
            let q = params.flatMap { $0 }.map { $0 & 0xFFFF }
            guard q.count == 48, slotOrder.count == 8, slotType.count == 8, stompMap.count == 4 else {
                throw PresetBankFile.FormatError("slot_order/slot_type need 8 entries, stomp_map 4, params 8 rows of 6")
            }
            func b(_ v: Int) -> UInt8 { UInt8(truncatingIfNeeded: v) }
            var r = [UInt8](repeating: 0, count: PresetRecord.size)
            let fl = (flags & ~1) | (empty ? 1 : 0)
            PresetRecord.put32(&r, 0, PresetRecord.magic); PresetRecord.put32(&r, 4, UInt32(truncatingIfNeeded: seq))
            for (i, u) in name.utf16.prefix(PresetRecord.maxNameLength).enumerated() { r[8 + i] = UInt8(truncatingIfNeeded: u) }
            PresetRecord.put16(&r, 32, UInt16(truncatingIfNeeded: bpm))
            r[34] = b(genre); r[35] = b(customCabIdx); r[36] = b(customCabBlend); r[37] = b(inputTrimDb); r[38] = b(gateThresholdPct); r[39] = b(slotEnableMask)
            for i in 0..<8 { r[40 + i] = b(slotOrder[i]); r[52 + i] = b(slotType[i]) }
            r[48] = b(ampModel); r[49] = b(cabModel); r[50] = b(presetVol); r[51] = b(fl)
            for i in 0..<4 { r[60 + i] = b(stompMap[i]) }
            for (i, v) in q.enumerated() { PresetRecord.put16(&r, 64 + 2 * i, UInt16(v)) }
            PresetRecord.put32(&r, 160, PresetRecord.crc32(r[0..<160]))
            return r
        }
    }

    // MARK: Writing

    /// `JSON.stringify(doc, null, 1) + "\n"`, which is the file the editor downloads.
    public func jsonData() -> Data {
        var w = JSONWriter()
        w.object([("format", .str(format)), ("version", .int(version)), ("record_size", .int(recordSize)), ("note", .str(note)),
                  ("presets", .arr(presets.map { $0.node }))], depth: 0)
        w.out += "\n"
        return Data(w.out.utf8)
    }
}

// MARK: JSON.stringify layout

private indirect enum Node {
    case int(Int), str(String), bool(Bool), arr([Node]), obj([(String, Node)])
}

private struct JSONWriter {
    var out = ""

    mutating func object(_ kv: [(String, Node)], depth: Int) { node(.obj(kv), depth) }

    mutating func node(_ n: Node, _ d: Int) {
        let pad = String(repeating: " ", count: d + 1), end = String(repeating: " ", count: d)
        switch n {
        case .int(let v): out += String(v)
        case .bool(let b): out += b ? "true" : "false"
        case .str(let s): string(s)
        case .arr(let a):
            if a.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, x) in a.enumerated() { out += pad; node(x, d + 1); out += i == a.count - 1 ? "\n" : ",\n" }
            out += end + "]"
        case .obj(let o):
            if o.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, kv) in o.enumerated() { out += pad; string(kv.0); out += ": "; node(kv.1, d + 1); out += i == o.count - 1 ? "\n" : ",\n" }
            out += end + "}"
        }
    }

    mutating func string(_ s: String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += "\\u" + String(format: "%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }
}

private extension PresetBankDocument.Item {
    var node: Node {
        switch self {
        case .unreadable(let s): return .obj([("slot", .int(s)), ("unreadable", .bool(true))])
        case .preset(let e):
            func ints(_ a: [Int]) -> Node { .arr(a.map { .int($0) }) }
            func rows(_ a: [[Int]]) -> Node { .arr(a.map { ints($0) }) }
            return .obj([
                ("slot", .int(e.slot)), ("name", .str(e.name)), ("empty", .bool(e.empty)), ("seq", .int(e.seq)), ("bpm", .int(e.bpm)), ("genre", .int(e.genre)),
                ("custom_cab_idx", .int(e.customCabIdx)), ("custom_cab_blend", .int(e.customCabBlend)), ("input_trim_db", .int(e.inputTrimDb)),
                ("gate_threshold_pct", .int(e.gateThresholdPct)), ("slot_enable_mask", .int(e.slotEnableMask)), ("slot_order", ints(e.slotOrder)),
                ("amp_model", .int(e.ampModel)), ("cab_model", .int(e.cabModel)), ("preset_vol", .int(e.presetVol)), ("flags", .int(e.flags)),
                ("slot_type", ints(e.slotType)), ("stomp_map", ints(e.stompMap)), ("params", rows(e.params)), ("params_pct", rows(e.paramsPct)),
            ])
        }
    }
}

// MARK: Lenient reading

/// A JSON value as the editor's typed-array stores and `Number()` / `String()` see it.
private indirect enum LenientValue: Decodable {
    case null, num(Double), bool(Bool), str(String), array([LenientValue]), object

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .num(d) }
        else if let s = try? c.decode(String.self) { self = .str(s) }
        else if let a = try? c.decode([LenientValue].self) { self = .array(a) }
        else { self = .object }
    }

    var number: Double {
        switch self {
        case .num(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        case .str(let s): return JS.number(s)
        case .array: return JS.number(string)
        case .object: return .nan
        }
    }

    /// ToInt32-like wrap, kept in an Int: `& 0xFF`, `>>> 0` and typed-array stores all take the low bits of it.
    var int: Int {
        let d = number
        guard d.isFinite else { return 0 }
        return Int(truncatingIfNeeded: Int64(fmod(d.rounded(.towardZero), 4294967296)))
    }

    var truthy: Bool {
        switch self {
        case .num(let d): return d != 0 && !d.isNaN
        case .bool(let b): return b
        case .str(let s): return !s.isEmpty
        case .array, .object: return true
        case .null: return false
        }
    }

    var string: String {
        switch self {
        case .str(let s): return s
        case .num(let d): return JS.numberString(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return a.map { if case .null = $0 { return "" } else { return $0.string } }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }
}

private enum Lenient {
    static func value<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> LenientValue? { try? c.decode(LenientValue.self, forKey: k) }
    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Int { value(c, k)?.int ?? 0 }
    static func truthy<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Bool { value(c, k)?.truthy ?? false }
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> String { value(c, k)?.string ?? "undefined" }

    static func ints<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> [Int] {
        if case .array(let a)? = value(c, k) { return a.map { $0.int } }
        return []
    }

    /// `[].concat(...params)` takes rows and bare numbers alike.
    static func rows<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> [[Int]] {
        guard case .array(let a)? = value(c, k) else { return [] }
        return a.map { if case .array(let r) = $0 { return r.map { $0.int } } else { return [$0.int] } }
    }
}
