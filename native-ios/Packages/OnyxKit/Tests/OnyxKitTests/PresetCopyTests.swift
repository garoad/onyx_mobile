// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// "Save as" logic of `PresetCopy`, with hand-built expectations.
final class PresetCopyTests: XCTestCase {
    private func stored(name: String = "Clean", flags: UInt8 = 0) -> PresetRecord {
        PresetRecord(seq: 9, name: name, bpm: 133, genre: 2, customCabIdx: 255, customCabBlend: 40, inputTrimDb: -3, gateThresholdPct: 25,
                     slotEnableMask: 0b0000_1101, slotOrder: [0, 1, 2, 3, 4, 5, 6, 7], ampModel: 5, cabModel: 6, presetVol: 70, flags: flags,
                     slotType: [0, 1, 5, 6, 3, 4, 2, 7], stompMap: [2, 5, 6, 7],
                     params: (0..<8).map { s in (0..<6).map { k in UInt16(1000 * (s * 6 + k) + 17) } })
    }

    /// The live state that equals `r`: same percentages, mask, order, types and stomp map.
    private func live(like r: PresetRecord, userCab: Bool = false) -> DeviceState {
        var rec = [UInt8](repeating: 0, count: 128)
        rec[0] = 1; rec[4] = r.presetVol; rec[116] = userCab ? 1 : 0
        for s in 0..<8 {
            let o = 22 + s * 8
            rec[o] = (r.slotEnableMask >> UInt8(s)) & 1; rec[o + 1] = r.slotType[s]
            for k in 0..<6 { rec[o + 2 + k] = UInt8(PresetRecord.percent(q16: r.params[s][k])) }
        }
        for i in 0..<8 { rec[117 + i] = r.slotOrder[i] }
        for i in 0..<4 { rec[111 + i] = r.stompMap[i] }
        return DeviceState.decode(rec)!
    }

    func testUnchangedLiveKeepsTheStoredRecord() {
        let s = stored()
        let l = live(like: s)
        XCTAssertEqual(PresetCopy.overlay(s, live: l), s)           // untouched Q16 knobs are not rounded to percentages
        XCTAssertFalse(PresetCopy.hasUnsavedChanges(stored: s, live: l))
    }

    func testChangedKnobBecomesPercentQ16AndOthersKeepFullResolution() {
        let s = stored()
        var l = live(like: s)
        l.slots[2].knobs[3] = 64
        let o = PresetCopy.overlay(s, live: l)
        XCTAssertEqual(o.params[2][3], PresetRecord.q16(percent: 64))
        XCTAssertEqual(o.params[2][3], 41942)                       // (64 * 65535 + 50) / 100
        for sl in 0..<8 { for k in 0..<6 where !(sl == 2 && k == 3) { XCTAssertEqual(o.params[sl][k], s.params[sl][k]) } }
        XCTAssertTrue(PresetCopy.hasUnsavedChanges(stored: s, live: l))
    }

    func testMaskOrderStompVolumeAndTypes() {
        let s = stored()
        var l = live(like: s)
        for i in 0..<8 { l.slots[i].on = (i % 2 == 1) }              // 1, 3, 5, 7
        l.order = [7, 6, 5, 4, 3, 2, 1, 0]
        l.stomp = [0, 1, 2, 3]
        l.presetVol = 55
        l.slots[2].type = 11                                         // AMP
        l.slots[3].type = 12                                         // CAB
        l.slots[5].type = 3                                          // MOD
        let o = PresetCopy.overlay(s, live: l)
        XCTAssertEqual(o.slotEnableMask, 0b1010_1010)
        XCTAssertEqual(o.slotOrder, [7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertEqual(o.stompMap, [0, 1, 2, 3])
        XCTAssertEqual(o.presetVol, 55)
        XCTAssertEqual(o.slotType[2], 11); XCTAssertEqual(o.slotType[3], 12); XCTAssertEqual(o.slotType[5], 3)
        XCTAssertEqual(o.ampModel, 11)
        XCTAssertEqual(o.cabModel, 12)
        // not part of the live state: they stay as stored
        XCTAssertEqual([o.bpm, UInt16(o.genre), UInt16(o.customCabBlend), UInt16(o.gateThresholdPct)], [133, 2, 40, 25])
        XCTAssertEqual(o.inputTrimDb, -3)
        XCTAssertEqual(o.customCabIdx, 255)
        XCTAssertEqual(o.name, "Clean")
        XCTAssertEqual(o.seq, 9)
    }

    func testUserCabKeepsTheStoredCabinetType() {
        let s = stored()
        var l = live(like: s, userCab: true)
        l.slots[3].type = 30                                         // the RAM user cab, cannot be stored
        l.slots[2].type = 9
        let o = PresetCopy.overlay(s, live: l)
        XCTAssertEqual(o.slotType[3], 6)
        XCTAssertEqual(o.cabModel, 6)
        XCTAssertEqual(o.slotType[2], 9)                             // only the cab is protected
        XCTAssertEqual(o.ampModel, 9)
    }

    func testRecordClearsEmptyAndCutsTheName() {
        let s = stored(name: "Old", flags: 0b101)
        XCTAssertTrue(s.isEmpty)
        let r = PresetCopy.record(base: s, live: nil, name: String(repeating: "N", count: 40))
        XCTAssertEqual(r.name, String(repeating: "N", count: 23))
        XCTAssertFalse(r.isEmpty)
        XCTAssertEqual(r.flags, 0b100)                               // other flag bits stay
        XCTAssertEqual(r.params, s.params)
        XCTAssertTrue(PresetRecord.isValid(r.encode()))
        let withLive = PresetCopy.record(base: s, live: live(like: s), name: "Copy")
        XCTAssertEqual(withLive.name, "Copy")
        XCTAssertFalse(withLive.isEmpty)
        XCTAssertEqual(PresetCopy.record(base: stored(), live: nil, name: "").name, "")
    }

    func testRecordWithLiveOverlaysBeforeNaming() {
        let s = stored()
        var l = live(like: s)
        l.presetVol = 12
        let r = PresetCopy.record(base: s, live: l, name: "Loud")
        XCTAssertEqual(r.presetVol, 12)
        XCTAssertEqual(r.name, "Loud")
        XCTAssertEqual(PresetRecord(record: r.encode()), r)
    }

    func testSuggestedName() {
        XCTAssertEqual(PresetCopy.suggestedName(for: "Clean"), "Clean 2")
        XCTAssertEqual(PresetCopy.suggestedName(for: "Clean 2"), "Clean 3")
        XCTAssertEqual(PresetCopy.suggestedName(for: "Clean 9"), "Clean 10")
        XCTAssertEqual(PresetCopy.suggestedName(for: "Clean 99"), "Clean 100")
        XCTAssertEqual(PresetCopy.suggestedName(for: "  Clean  "), "Clean 2")
        XCTAssertEqual(PresetCopy.suggestedName(for: ""), "NEW")
        XCTAssertEqual(PresetCopy.suggestedName(for: "   "), "NEW")
        XCTAssertEqual(PresetCopy.suggestedName(for: "Rock 2024"), "Rock 2024 2")
        for n in [21, 22, 23, 24, 30] {
            let s = PresetCopy.suggestedName(for: String(repeating: "A", count: n))
            XCTAssertLessThanOrEqual(s.count, 23, "\(n)")
            XCTAssertTrue(s.hasSuffix(" 2"), s)
        }
        XCTAssertEqual(PresetCopy.suggestedName(for: String(repeating: "A", count: 23)), String(repeating: "A", count: 21) + " 2")
        let numbered = String(repeating: "B", count: 20) + " 99"
        XCTAssertEqual(PresetCopy.suggestedName(for: numbered), String(repeating: "B", count: 19) + " 100")
        XCTAssertEqual(PresetCopy.suggestedName(for: numbered).count, 23)
    }

    func testSameSoundIgnoresSeqOnly() {
        let a = stored()
        var b = a
        b.seq = 12345
        XCTAssertTrue(PresetCopy.sameSound(a, b))
        b.params[0][0] &+= 1
        XCTAssertFalse(PresetCopy.sameSound(a, b))
        var c = a
        c.name = "Other"
        XCTAssertFalse(PresetCopy.sameSound(a, c))
        var d = a
        d.isEmpty = true
        XCTAssertFalse(PresetCopy.sameSound(a, d))
    }

    func testUploadTargetIsPresetSave() { XCTAssertEqual(PresetCopy.uploadTarget, 0) }
}
