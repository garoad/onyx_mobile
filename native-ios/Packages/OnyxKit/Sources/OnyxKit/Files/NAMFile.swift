// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The amp capture file the unit takes (`stripNam` / `namJson` of the web editor): a ToneHunt `.nam` (JSON) is converted to the unit's WaveNet blob,
/// a `.namb` container, a raw model struct or a `WAVE` blob is only cut to size.
public enum NAMFile {
    public struct Result: Equatable, Sendable {
        /// What to upload (nil on error).
        public var bytes: [UInt8]?
        /// What the status line says about the conversion.
        public var how: String?
        /// The capture's name from its metadata (only for a `.nam`).
        public var name: String?
        /// The output makeup in dB (quarter-dB steps) and whether the capture has its cabinet baked in (only for a `.nam`).
        public var makeupDb: Double?
        public var cabinetBakedIn: Bool?
        public var error: String?
    }

    /// The unit's capture slot holds at most this many bytes.
    public static let maxBlobSize = 8192

    static let adcRefDbu = 4.0
    static let targetDb = -15.5, cabDb = -4.0

    private static func failure(_ s: String) -> Result { Result(error: s) }

    /// `stripNam(f, filename)`.
    public static func convert(_ f: [UInt8], filename: String) -> Result {
        let n = f.count
        var i = 0
        if n >= 3, f[0] == 0xEF, f[1] == 0xBB, f[2] == 0xBF { i = 3 }
        while i < n, f[i] == 0x20 || f[i] == 0x0A || f[i] == 0x0D || f[i] == 0x09 { i += 1 }
        if i < n, f[i] == 0x7B { return json(f, filename: filename) }
        let head = Array(f.prefix(4))
        if head == Array("WAVE".utf8) {
            return n <= maxBlobSize ? Result(bytes: f, how: "WaveNet blob, sent as it is") : failure("a WaveNet blob over 8192 bytes does not fit the unit")
        }
        if n == 3852 || n == 4040 { return Result(bytes: Array(f[0..<3852]), how: "raw \(n) B struct, first 3852 B") }
        if head.starts(with: [0x40, 0x4D]) || head == [0x4E, 0x41, 0x4D, 0] {
            var shown = head
            if let z = shown.firstIndex(of: 0) { shown.remove(at: z) }
            let tag = String(String.UnicodeScalarView(shown.map { Unicode.Scalar($0) }))
            if n >= 6204 + 3852 { return Result(bytes: Array(f[6204..<(6204 + 3852)]), how: "\(tag) container, model struct at +6204 (3852 B)") }
            if n >= 3852 { return Result(bytes: Array(f[0..<3852]), how: "\(tag) short container, first 3852 B") }
        }
        return failure("unknown format (\(n) bytes): expected a .namb container, a 3852 / 4040 B struct or a WAVE blob")
    }

    // MARK: .nam (JSON)

    private static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    // JavaScript's \b only knows ASCII word characters
    private static let wb = "(?<![A-Za-z0-9_])", we = "(?![A-Za-z0-9_])"
    private static let noCab = regex(#"cab[ _\-]*free|no[ _\-]*cab|without[ _\-]*cab|w/o[ _\-]*cab|cabless|cab[ _\-]*less|amp[ _\-]*only|di[ _\-]*out|direct[ _\-]*out"#)
    private static let hasCab = regex("cab|full[ _\\-]*rig|^fr[ _\\-]|\(wb)sm ?5[78]\(we)|\(wb)md ?421\(we)|\(wb)e ?609\(we)|\(wb)r ?121\(we)|\(wb)u ?87\(we)|\(wb)mic(ed|'d)?\(we)")

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil
    }

    /// `namHasBakedCab`: a capture names its cabinet ("CAB", "Full Rig", a microphone model ...).
    static func hasBakedCab(gear: String, name: String, file: String) -> Bool {
        let names = [name.lowercased(), file.lowercased()]
        if names.contains(where: { matches(noCab, $0) }) { return false }
        return gear.contains("cab") || names.contains(where: { matches(hasCab, $0) })
    }

    /// `namLoudness`: the capture's output loudness in dB, if the file has one.
    static func loudness(meta: JSONValue, data: JSONValue) -> Double? {
        for o in [meta, data["metadata"], data].compactMap({ $0 }) where o.isObject {
            for k in ["loudness", "output_loudness", "loudness_db"] {
                guard let raw = o[k] else { continue }
                if case .null = raw { continue }
                let v = raw.jsNumber
                if v.isFinite { return v }
            }
        }
        return nil
    }

    /// `namMakeupDb`: puts the capture at the stock amps' level, in quarter-dB steps.
    static func makeupDb(loud: Double?, cab: Bool) -> Double {
        guard let loud else { return 0 }
        let db = targetDb - loud + (cab ? cabDb : 0)
        return JS.round(JS.max(-12, JS.min(12, db)) * 4) / 4
    }

    /// `namInputLevel`: the recorded input level in dBu, if the file has one.
    static func inputLevel(meta: JSONValue, data: JSONValue) -> Double? {
        for o in [meta, data["metadata"], data["config"], data].compactMap({ $0 }) where o.isObject {
            for k in ["input_level_dbu", "input_level", "input_dBu", "calibration_dBu"] {
                guard let raw = o[k] else { continue }
                if case .null = raw { continue }
                let v = raw.jsNumber
                if !v.isNaN { return v }
            }
        }
        return nil
    }

    private static func float32(_ d: Double) -> UInt32 { d.isNaN ? 0x7FC0_0000 : Float(d).bitPattern }

    /// `namJson`: the unit's WaveNet blob is 'WAVE', weight count u32, head scale f32, flags u32, input trim f32, then the f32 weights (all little endian).
    static func json(_ f: [UInt8], filename: String) -> Result {
        let data: JSONValue
        do { data = try JSONValue.parse(utf8: f) } catch let e as JSONValue.ParseError { return failure("this file is not valid JSON (\(e.message))") } catch { return failure("this file is not valid JSON") }
        var m: JSONValue?, ws: [JSONValue] = []
        if case .string("SlimmableContainer")? = data["architecture"] {
            var subs: [JSONValue] = []
            if case .array(let a)? = data["config"]?["submodels"] { subs = a }
            for sm in subs {
                guard let model = sm["model"], model.truthy else { continue }
                if case .array(let w)? = model["weights"], w.count == 1870 || w.count == 1871 { m = model; ws = w; break }
            }
            if m == nil { return failure("this capture has no A2 Lite model (3 channels, 1870 / 1871 weights): the unit takes the Lite one, the Full model is 48 KB and does not fit its 8 KB slot") }
        } else if case .string("WaveNet")? = data["architecture"], case .array(let w)? = data["weights"], w.count == 1870 || w.count == 1871 {
            m = data; ws = w
        } else {
            return failure("unknown .nam: expected a ToneHunt A2 capture (SlimmableContainer with a Lite WaveNet) or a 3-channel WaveNet")
        }
        guard let m else { return failure("unknown .nam") }
        var head = 1.0
        // `(m.config && m.config.head_scale) !== undefined ? Number(m.config.head_scale) : 1.0`: a falsy config reads head_scale off itself (NaN), null throws
        if let c = m["config"] {
            if case .null = c { return failure("Cannot read properties of null (reading 'head_scale')") }
            head = c.truthy ? (c["head_scale"]?.jsNumber ?? 1.0) : .nan
        }
        var weights = ws.map { $0.jsNumber }
        if weights.count == 1870 { weights.append(head) }
        if weights.contains(where: { !$0.isFinite }) { return failure("the weights contain a value that is not a number") }
        var meta: JSONValue = .object([:])
        if let a = m["metadata"], a.truthy { meta = a } else if let b = data["metadata"], b.truthy { meta = b }
        var name = filename.isEmpty ? "NAM" : filename
        if let v = meta["name"], v.truthy { name = v.jsString } else if let v = meta["gear_model"], v.truthy { name = v.jsString }
        let gear = (meta["gear_type"].flatMap { $0.truthy ? $0.jsString : nil } ?? "").lowercased()
        let cab = hasBakedCab(gear: gear, name: name, file: filename)
        let lvl = inputLevel(meta: meta, data: data)
        let trim = lvl.map { JS.numberFixed4(pow(10, (adcRefDbu - $0) / 20)) } ?? 1.0
        let loud = loudness(meta: meta, data: data)
        let mk = makeupDb(loud: loud, cab: cab)
        // flags: bit 0 the cabinet is baked in, bit 1 a makeup is given, bits 8..15 the makeup as a signed quarter-dB (an older firmware reads bit 0 only)
        var flags: UInt32 = cab ? 1 : 0
        if loud != nil { flags |= 2 | UInt32(UInt8(truncatingIfNeeded: Int(mk * 4))) << 8 }
        var out = [UInt8](repeating: 0, count: 20 + weights.count * 4)
        out.replaceSubrange(0..<4, with: [0x57, 0x41, 0x56, 0x45])
        func put(_ at: Int, _ v: UInt32) { for k in 0..<4 { out[at + k] = UInt8(truncatingIfNeeded: v >> UInt32(8 * k)) } }
        put(4, UInt32(weights.count)); put(8, float32(head)); put(12, flags); put(16, float32(trim))
        for (i, w) in weights.enumerated() { put(20 + 4 * i, float32(w)) }
        var how = "ToneHunt .nam converted: A2 Lite WaveNet, \(weights.count) weights"
        if cab { how += ", cabinet baked in" }
        if lvl != nil { how += ", input trim \(JS.numberString(trim))" }
        how += loud != nil ? ", level matched to the stock amps (\(mk >= 0 ? "+" : "")\(JS.numberString(mk)) dB)" : ", no loudness in the file: played at its recorded level"
        return Result(bytes: out, how: how, name: name, makeupDb: mk, cabinetBakedIn: cab)
    }
}
