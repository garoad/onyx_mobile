// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// `PresetRecord` against `presetToRecord` / `recordToPreset` / `recordOk` / `crc32` of the original JavaScript (Tools/golden/gen_protocol.cjs).
/// The JS `recordToPreset` does not validate its input; `PresetRecord.init?(record:)` returns nil for a record that fails `recordOk`, so decoding is only compared for valid records.
final class PresetRecordGoldenTests: XCTestCase {
    private struct JSIn: Decodable {
        let seq: UInt32; let name: String; let bpm: UInt16; let genre: UInt8; let custom_cab_idx: UInt8; let custom_cab_blend: UInt8
        let input_trim_db: Int8; let gate_threshold_pct: UInt8; let slot_enable_mask: UInt8; let slot_order: [UInt8]
        let amp_model: UInt8; let cab_model: UInt8; let preset_vol: UInt8; let flags: UInt8?; let empty: Bool
        let slot_type: [UInt8]; let stomp_map: [UInt8]; let params: [[UInt16]]
    }
    private struct JSPreset: Decodable {
        let name: String; let empty: Bool; let seq: UInt32; let bpm: UInt16; let genre: UInt8; let custom_cab_idx: UInt8; let custom_cab_blend: UInt8
        let input_trim_db: Int8; let gate_threshold_pct: UInt8; let slot_enable_mask: UInt8; let slot_order: [UInt8]
        let amp_model: UInt8; let cab_model: UInt8; let preset_vol: UInt8; let flags: UInt8; let slot_type: [UInt8]; let stomp_map: [UInt8]
        let params: [[UInt16]]; let params_pct: [[Int]]
    }
    private struct Made: Decodable { let `in`: JSIn; let record: String; let ok: Bool; let preset: JSPreset }
    private struct Raw: Decodable { let note: String; let record: String; let ok: Bool; let preset: JSPreset? }
    private struct CRC: Decodable { let `in`: String; let crc: UInt32 }
    private struct Doc: Decodable { let presets: [Made]; let raw: [Raw]; let crc: [CRC]; let pct: [[Int]]; let q16: [[Int]] }

    private var doc: Doc!
    override func setUpWithError() throws { doc = try Fixtures.load("presetrecord") }

    private func record(from o: JSIn) -> PresetRecord {
        PresetRecord(seq: o.seq, name: o.name, bpm: o.bpm, genre: o.genre, customCabIdx: o.custom_cab_idx, customCabBlend: o.custom_cab_blend,
                     inputTrimDb: o.input_trim_db, gateThresholdPct: o.gate_threshold_pct, slotEnableMask: o.slot_enable_mask, slotOrder: o.slot_order,
                     ampModel: o.amp_model, cabModel: o.cab_model, presetVol: o.preset_vol, flags: ((o.flags ?? 0) & ~1) | (o.empty ? 1 : 0),
                     slotType: o.slot_type, stompMap: o.stomp_map, params: o.params)
    }

    private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    private func assertSame(_ r: PresetRecord, _ e: JSPreset, _ ctx: String) {
        XCTAssertEqual(scalars(r.name), scalars(e.name), "name \(ctx)")
        XCTAssertEqual(r.isEmpty, e.empty, ctx)
        XCTAssertEqual([r.seq, UInt32(r.bpm)], [e.seq, UInt32(e.bpm)], ctx)
        XCTAssertEqual([r.genre, r.customCabIdx, r.customCabBlend, r.gateThresholdPct, r.slotEnableMask],
                       [e.genre, e.custom_cab_idx, e.custom_cab_blend, e.gate_threshold_pct, e.slot_enable_mask], ctx)
        XCTAssertEqual(r.inputTrimDb, e.input_trim_db, ctx)
        XCTAssertEqual([r.ampModel, r.cabModel, r.presetVol, r.flags], [e.amp_model, e.cab_model, e.preset_vol, e.flags], ctx)
        XCTAssertEqual(r.slotOrder, e.slot_order, ctx)
        XCTAssertEqual(r.slotType, e.slot_type, ctx)
        XCTAssertEqual(r.stompMap, e.stomp_map, ctx)
        XCTAssertEqual(r.params, e.params, ctx)
        XCTAssertEqual(r.params.map { $0.map { PresetRecord.percent(q16: $0) } }, e.params_pct, "params_pct \(ctx)")
    }

    func testEncodeMatchesJS() {
        XCTAssertGreaterThan(doc.presets.count, 70)
        var longNames = 0, negTrim = 0, empties = 0
        for v in doc.presets {
            let r = record(from: v.in)
            XCTAssertEqual(r.encode(), Fixtures.bytes(v.record), "encode \(v.in.name.debugDescription)")
            if v.in.name.utf16.count > 23 { longNames += 1 }
            if v.in.input_trim_db < 0 { negTrim += 1 }
            if v.in.empty { empties += 1 }
            XCTAssertTrue(v.ok)
            XCTAssertTrue(PresetRecord.isValid(Fixtures.bytes(v.record)))
        }
        XCTAssertGreaterThan(longNames, 5)
        XCTAssertGreaterThan(negTrim, 10)
        XCTAssertGreaterThan(empties, 10)
    }

    func testDecodeMatchesJS() {
        for v in doc.presets {
            let bytes = Fixtures.bytes(v.record)
            guard let r = PresetRecord(record: bytes) else { XCTFail("nil for \(v.in.name.debugDescription)"); continue }
            assertSame(r, v.preset, v.in.name.debugDescription)
            // a character whose low byte is 0 ends the name when read back, so only the others re-encode to the same bytes
            if !v.in.name.utf16.prefix(23).contains(where: { $0 & 0xFF == 0 }) { XCTAssertEqual(r.encode(), bytes, "re-encode \(v.in.name.debugDescription)") }
        }
    }

    func testRawRecords() {
        XCTAssertGreaterThan(doc.raw.count, 100)
        var valid = 0, invalid = 0
        for v in doc.raw {
            let bytes = Fixtures.bytes(v.record)
            XCTAssertEqual(PresetRecord.isValid(bytes), v.ok, "\(v.note) \(v.record)")
            let r = PresetRecord(record: bytes)
            if let e = v.preset {
                valid += 1
                guard let r else { XCTFail("nil for valid \(v.note)"); continue }
                assertSame(r, e, v.note)
            } else {
                invalid += 1
                XCTAssertNil(r, v.note)       // the JS would decode it anyway; the Swift initialiser refuses
            }
        }
        XCTAssertGreaterThan(valid, 30)
        XCTAssertGreaterThan(invalid, 40)
    }

    func testCRC32() {
        XCTAssertEqual(PresetRecord.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertGreaterThan(doc.crc.count, 15)
        for v in doc.crc {
            let b = Fixtures.bytes(v.in)
            XCTAssertEqual(PresetRecord.crc32(b), v.crc, v.in)
            XCTAssertEqual(PresetRecord.crc32(b[...]), v.crc, v.in)
        }
    }

    func testPercentOfQ16() {
        XCTAssertGreaterThan(doc.pct.count, 700)
        for p in doc.pct { XCTAssertEqual(PresetRecord.percent(q16: UInt16(p[0])), p[1], "q16 \(p[0])") }
    }

    func testQ16OfPercent() {
        XCTAssertEqual(doc.q16.count, 151)
        for p in doc.q16 { XCTAssertEqual(Int(PresetRecord.q16(percent: p[0])), p[1], "percent \(p[0])") }
        for p in 0...100 { XCTAssertEqual(PresetRecord.percent(q16: PresetRecord.q16(percent: p)), p, "round trip \(p)") }
    }
}
