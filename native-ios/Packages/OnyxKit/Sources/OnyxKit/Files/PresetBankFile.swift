// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// Preset bank files: the `pocket-amp-presets` JSON backup (`PresetBankDocument`) and the stock app's `.abkx` bank, which is converted to that document
/// (`abkxConvert`, a port of `abkx_to_json.py`). Records come from and go to `[PresetRecord?]`.
public enum PresetBankFile {
    /// A file that is not what it should be; `description` is the editor's message.
    public struct FormatError: Error, LocalizedError, Equatable, Sendable {
        public var message: String
        init(_ m: String) { message = m }
        public var errorDescription: String? { message }
    }

    public struct AbkxOptions: Equatable, Sendable {
        /// Keep the stock chain order (DRIVE goes directly before AMP, EQ directly after CAB).
        public var preserveChain = false
        /// Copy the stock AMP Level knob into MASTER (the importer's default leaves it at 50).
        public var copyAmpLevel = false
        public var namePrefix = "P"
        /// 0...7
        public var genre = 7
        public init(preserveChain: Bool = false, copyAmpLevel: Bool = false, namePrefix: String = "P", genre: Int = 7) {
            self.preserveChain = preserveChain; self.copyAmpLevel = copyAmpLevel; self.namePrefix = namePrefix; self.genre = genre
        }
    }

    public static let abkxRecordSize = 92, abkxTrailerSize = 10, abkxSize = PresetRecord.count * abkxRecordSize + abkxTrailerSize

    // MARK: JSON documents

    /// A `.json` backup. Throws `FormatError("not a JSON file")` for a file that is not JSON and `FormatError("not a pocket-amp-presets file")` for JSON that is not a backup.
    public static func parse(data: Data) throws -> PresetBankDocument {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        guard (try? JSONValue.parse(utf8: Array(d))) != nil else { throw FormatError("not a JSON file") }
        do { return try JSONDecoder().decode(PresetBankDocument.self, from: d) } catch let e as FormatError { throw e } catch { throw FormatError("not a pocket-amp-presets file") }
    }

    /// `presetsFromDoc`: 80 records, nil where a preset is missing, unreadable or its slot number is out of range (the last entry for a slot wins).
    /// Throws when an entry's arrays have the wrong length.
    public static func recordBytes(_ doc: PresetBankDocument) throws -> [[UInt8]?] {
        var out = [[UInt8]?](repeating: nil, count: PresetRecord.count)
        for item in doc.presets {
            guard case .preset(let e) = item else { continue }
            let i = Int(Int32(truncatingIfNeeded: e.slot)) - 1
            if i >= 0 && i < PresetRecord.count { out[i] = try e.recordBytes() }
        }
        return out
    }

    public static func records(_ doc: PresetBankDocument) throws -> [PresetRecord?] {
        try recordBytes(doc).map { $0.flatMap { PresetRecord(record: $0) } }
    }

    /// The document the editor builds from a read of the unit (`nil` = the unit could not deliver that slot).
    public static func document(from records: [PresetRecord?]) -> PresetBankDocument {
        PresetBankDocument(note: PresetBankDocument.unitNote, presets: records.enumerated().map { i, r in
            r.map { .preset(.init(index: i, record: $0)) } ?? .unreadable(slot: i + 1)
        })
    }

    // MARK: .abkx

    private enum Code { static let fx = 0, amp = 1, mod = 2, dly = 3, rev = 4, cab = 5 }
    private static let slotOffset = [0x14, 0x20, 0x2C, 0x38, 0x44, 0x50]          // FX AMP MOD DLY REV CAB
    private enum OS { static let dyn = 0, drive = 1, amp = 2, cab = 3, eq = 4, mod = 5, dly = 6, rev = 7 }
    private static let chainSlot = [OS.dyn, OS.amp, OS.mod, OS.dly, OS.rev, OS.cab]
    private static let modType = [0: 0, 1: 1, 2: 3, 3: 2, 4: 4, 5: 5, 6: 6]
    private static let dlyExt = [1: 5, 2: 6, 3: 7, 4: 8], revExt = [1: 6, 2: 0]

    private static func pct(_ v: Int) -> Int { max(0, min(100, v)) }
    private static func q16(_ v: Int) -> Int { (pct(v) * 65535 + 50) / 100 }

    private static func neutral() -> [[Int]] {
        var p = [[Int]](repeating: [50, 50, 50, 50, 50, 50], count: 8)
        p[OS.dyn][3] = 100; p[OS.cab][0] = 100; p[OS.cab][1] = 0; p[OS.cab][2] = 0; p[OS.mod][2] = 12; p[OS.dly][1] = 15; p[OS.dly][2] = 10; p[OS.rev][1] = 0
        return p
    }

    private struct Ext { var dlyExt, revExt, dynExt, ampPres, inputTrimDb, driveOn, driveType, eqOn, eqType, driveDrive, driveTone, driveLevel: Int; var eqK: [Int] }

    private static func ext(_ r: ArraySlice<UInt8>) -> Ext? {
        let b = r.startIndex
        func at(_ o: Int) -> Int { Int(r[b + o]) }
        guard at(1) & 0x80 != 0, (at(1) >> 5) & 3 == 1 else { return nil }
        let c = at(1) & 0x1F
        return Ext(dlyExt: c % 5, revExt: c / 5 % 3, dynExt: c / 15, ampPres: at(0x2A), inputTrimDb: at(0x2B) - 50, driveOn: at(0x36) / 50, driveType: at(0x36) % 50,
                   eqOn: at(0x4E) / 50, eqType: at(0x4E) % 50, driveDrive: at(0x56), driveTone: at(0x58), driveLevel: at(0x5A), eqK: [at(0x37), at(0x4F), at(0x57), at(0x59), at(0x5B)])
    }

    private static func empty(slot: Int, genre: Int) -> PresetBankDocument.Entry {
        let p = neutral()
        return .init(slot: slot, name: "EMPTY", empty: true, seq: 1, bpm: 120, genre: genre, customCabIdx: 255, customCabBlend: 100, inputTrimDb: 0, gateThresholdPct: 0,
                     slotEnableMask: 0, slotOrder: [0, 1, 2, 3, 4, 5, 6, 7], ampModel: 0, cabModel: 0, presetVol: 70, flags: 1, slotType: [3, 0, 0, 0, 0, 0, 0, 0],
                     stompMap: [1, 5, 6, 7], params: p.map { $0.map(q16) }, paramsPct: p)
    }

    private static func preset(_ r: ArraySlice<UInt8>, _ index: Int, _ o: AbkxOptions, genre: Int) -> PresetBankDocument.Entry {
        let b = r.startIndex
        func at(_ off: Int) -> Int { Int(r[b + off]) }
        func params(_ code: Int) -> [Int] { (0..<6).map { k in at(slotOffset[code] + 2 * k) | at(slotOffset[code] + 2 * k + 1) << 8 } }
        let ext = ext(r), en = (0..<6).map { at(0x08 + $0) }, driveOn = (ext?.driveOn ?? 0) != 0, eqOn = (ext?.eqOn ?? 0) != 0
        if !en.contains(where: { $0 != 0 }) && !driveOn && !eqOn { return empty(slot: index + 1, genre: genre) }
        var p = neutral(), t = [Int](repeating: 0, count: 8), mask = 0, ampT = 0, cabT = 0
        do { // DYN
            let v = params(Code.fx)
            var ty = at(0x0E)
            if ext?.dynExt == 1 { ty = 4 }
            let ok = (0...4).contains(ty)
            if !ok { ty = 0 }
            if ok {
                p[OS.dyn][0] = pct(v[0])
                if ty == 1 { p[OS.dyn][3] = pct(v[1]) } else if ty == 2 || ty == 4 { p[OS.dyn][1] = pct(v[1]); p[OS.dyn][2] = pct(v[2]); p[OS.dyn][3] = pct(v[3] * 2) }
            }
            t[OS.dyn] = ty
            if en[0] != 0 && ok { mask |= 1 << OS.dyn }
        }
        do { // AMP
            let v = params(Code.amp), a = at(0x0E + 1)
            ampT = a < 20 ? a : 0
            p[OS.amp][0] = pct(v[0]); p[OS.amp][1] = pct(v[2]); p[OS.amp][2] = pct(v[3]); p[OS.amp][3] = pct(v[4])
            p[OS.amp][4] = ext.map { pct($0.ampPres) } ?? 50
            p[OS.amp][5] = o.copyAmpLevel ? pct(v[1]) : 50
            t[OS.amp] = ampT
            if en[1] != 0 { mask |= 1 << OS.amp }
        }
        do { // CAB
            let v = params(Code.cab), c = at(0x0E + 5)
            cabT = c < 20 ? c : 0
            p[OS.cab][0] = pct(v[0]); p[OS.cab][1] = pct(v[1]); p[OS.cab][2] = pct(100 - v[2])
            t[OS.cab] = cabT
            if en[5] != 0 { mask |= 1 << OS.cab }
        }
        do { // MOD
            let v = params(Code.mod), ty = modType[at(0x0E + 2)]
            if let ty {
                if ty == 0 { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct(v[1]); p[OS.mod][2] = pct(v[2]) }
                else if ty == 1 { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct(v[2]); p[OS.mod][3] = pct(v[3]) }
                else if ty == 2 { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct(v[1]); p[OS.mod][3] = pct(v[2]); p[OS.mod][2] = pct(v[3]) }
                else if ty == 3 || ty == 4 { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct(v[1]) }
                else if ty == 5 { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct(v[1]); p[OS.mod][2] = pct(v[2]) }      // UNIVIBE -> PHASER (below)
                else { p[OS.mod][0] = pct(v[0]); p[OS.mod][1] = pct((v[1] + v[2]) / 2); p[OS.mod][2] = pct(v[3]); p[OS.mod][3] = pct(v[4]) }
            }
            t[OS.mod] = ty.map { $0 == 5 ? 1 : $0 } ?? 0
            if en[2] != 0 && ty != nil { mask |= 1 << OS.mod }
        }
        do { // DLY
            let v = params(Code.dly)
            var ty = at(0x0E + 3)
            if let e = ext, e.dlyExt != 0, let m = dlyExt[e.dlyExt] { ty = m }
            if !(0...8).contains(ty) { ty = 0 }
            p[OS.dly][0] = pct(v[0]); p[OS.dly][1] = pct(v[1]); p[OS.dly][2] = pct(v[2]); p[OS.dly][3] = ty == 3 ? 0 : pct(v[3])
            t[OS.dly] = ty
            if en[3] != 0 { mask |= 1 << OS.dly }
        }
        do { // REV
            let v = params(Code.rev)
            var ty = at(0x0E + 4)
            if let e = ext, e.revExt != 0, let m = revExt[e.revExt] { ty = m }
            if !(0...6).contains(ty) { ty = 0 }
            if ty == 4 { p[OS.rev][0] = pct(v[0]); p[OS.rev][3] = pct(v[1]); p[OS.rev][2] = pct(v[2]) }
            else { p[OS.rev][0] = pct(v[0]); p[OS.rev][1] = pct(v[2]); p[OS.rev][2] = pct(v[3]); p[OS.rev][3] = pct(v[1]) }
            t[OS.rev] = ty
            if en[4] != 0 { mask |= 1 << OS.rev }
        }
        if driveOn, let e = ext {
            t[OS.drive] = e.driveType % 6
            p[OS.drive][0] = pct(e.driveDrive); p[OS.drive][1] = pct(e.driveTone); p[OS.drive][2] = pct(e.driveLevel)
            mask |= 1 << OS.drive
        }
        if eqOn, let e = ext {
            t[OS.eq] = e.eqType % 3
            for i in 0..<5 { p[OS.eq][i] = pct(e.eqK[i]) }
            mask |= 1 << OS.eq
        }
        var order = [0, 1, 2, 3, 4, 5, 6, 7]
        if o.preserveChain {
            order = []
            for code in (2..<8).map({ at($0) }) {
                let sl = chainSlot[code]
                if sl == OS.amp { order.append(OS.drive) }
                order.append(sl)
                if sl == OS.cab { order.append(OS.eq) }
            }
            for s in 0..<8 where !order.contains(s) { order.append(s) }
        }
        let trim = ext.map { max(-12, min(12, $0.inputTrimDb)) } ?? 0
        let name = String(decoding: Array((o.namePrefix + (index + 1 < 10 ? "0" : "") + String(index + 1)).utf16.prefix(PresetRecord.maxNameLength)), as: UTF16.self)
        return .init(slot: index + 1, name: name, empty: false, seq: 2, bpm: 120, genre: genre, customCabIdx: 255, customCabBlend: 100, inputTrimDb: trim, gateThresholdPct: 0,
                     slotEnableMask: mask, slotOrder: order, ampModel: ampT, cabModel: cabT, presetVol: pct(at(0)), flags: 0, slotType: t, stompMap: [1, 5, 6, 7],
                     params: p.map { $0.map(q16) }, paramsPct: p)
    }

    /// `abkxConvert`: a whole 7,370-byte bank (80 records of 92 bytes + `PATCHEND` + 2 bytes) -> the Onyx preset document.
    public static func abkx(_ data: [UInt8], options: AbkxOptions = .init()) throws -> PresetBankDocument {
        let genre = max(0, min(7, options.genre))
        guard data.count == abkxSize else { throw FormatError("expected \(abkxSize) bytes, got \(data.count)") }
        let trailer = PresetRecord.count * abkxRecordSize
        guard Array(data[trailer..<trailer + 8]) == Array("PATCHEND".utf8) else { throw FormatError("missing PATCHEND trailer") }
        let last = data[data.count - 1]
        guard last == 0 || last == 0x45 else { throw FormatError("unexpected trailer byte 0x" + String(last, radix: 16)) }
        var presets: [PresetBankDocument.Item] = []
        for i in 0..<PresetRecord.count {
            let r = data[i * abkxRecordSize..<(i + 1) * abkxRecordSize]
            guard r[(r.startIndex + 2)..<(r.startIndex + 8)].sorted() == [0, 1, 2, 3, 4, 5] else {
                throw FormatError("slot \(i + 1): chain order is not a permutation of 0..5")
            }
            presets.append(.preset(preset(r, i, options, genre: genre)))
        }
        return PresetBankDocument(note: PresetBankDocument.abkxNote, presets: presets)
    }
}
