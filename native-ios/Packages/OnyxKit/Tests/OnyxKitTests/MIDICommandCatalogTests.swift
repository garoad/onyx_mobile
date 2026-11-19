// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

final class MIDICommandCatalogTests: XCTestCase {
    private let all = MIDICommandCatalog.all

    // Hand-written from reference/firmware/usb_ble.c (handle_midi_cc, handle_midi_cc_off, handle_midi_pedal_event, nrpn_apply).
    // CC 90..94 (bench) are handled by the firmware but deliberately not in the catalog.
    private let firmwareButtonAndValueCCs: Set<Int> = {
        var s: Set<Int> = [7, 80, 81, 85, 86, 87, 88, 64, 65, 66, 67]
        for r in [20...27, 28...35, 102...118] { s.formUnion(r) }
        return s
    }()
    private let firmwareNRPNPlumbing: Set<Int> = [6, 38, 98, 99, 100, 101]
    private var firmwareNRPN: Set<String> {
        var s = Set<String>()
        for m in 0...7 {
            for p in Array(0...5) + [0x40, 0x41] + Array(0x60...0x65) { s.insert("\(m)/\(p)") }
        }
        for p in 0...19 { s.insert("8/\(p)") }       // GLOBAL: pa_settings ids 0..19 (MIDI-MAP-CUSTOM.md section 6)
        for p in 0...4 { s.insert("9/\(p)") }        // GROOVE
        for p in 0...7 { s.insert("10/\(p)") }       // PRESET (1, 2 accepted, no effect)
        return s
    }

    func testIdsUnique() {
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testExampleBytesAreValidMIDI() {
        for c in all {
            var i = 0
            let b = c.example
            XCTAssertFalse(b.isEmpty, c.id)
            while i < b.count {
                let st = b[i]
                XCTAssertTrue(st >= 0x80 && st < 0xF0, "\(c.id) status \(st)")
                let n = (st >> 4) == 0xC ? 1 : 2
                XCTAssertLessThanOrEqual(i + n, b.count - 1, "\(c.id) truncated")
                for d in b[(i + 1)...(i + n)] { XCTAssertLessThan(d, 0x80, "\(c.id) data byte \(d)") }
                i += n + 1
            }
        }
    }

    func testExampleMatchesMessage() {
        for c in all {
            switch c.message {
            case .programChange(let n):
                XCTAssertEqual(c.example, [0xC0, UInt8(n)])
                XCTAssertTrue((0..<80).contains(n))
            case .controlChange(let cc, _):
                XCTAssertEqual(c.example.count, 3, c.id)
                XCTAssertEqual(Array(c.example[0...1]), [0xB0, UInt8(cc)], c.id)
            case .nrpn(let m, let p, _):
                XCTAssertEqual(Array(c.example[0..<6]), [0xB0, 99, UInt8(m), 0xB0, 98, UInt8(p)], c.id)
                XCTAssertEqual(c.example[6], 0xB0); XCTAssertEqual(c.example[7], 6)
            }
        }
    }

    func testHexAndDecimal() {
        let c = MIDICommandCatalog.command(id: "cc.21")!
        XCTAssertEqual(c.hexString, "B0 15 7F")
        XCTAssertEqual(c.decimalString, "176 21 127")
        XCTAssertEqual(MIDICommandCatalog.command(id: "pc.12")!.hexString, "C0 0C")
    }

    func testCCSetEqualsFirmware() {
        let catalogCCs = Set(all.compactMap(\.ccNumber))
        XCTAssertEqual(catalogCCs, firmwareButtonAndValueCCs)
        XCTAssertTrue(catalogCCs.isDisjoint(with: [90, 91, 92, 93, 94, 119]), "bench-only and reserved CCs must not be listed")
        XCTAssertEqual(Set(MIDICommandCatalog.nrpnPlumbingCCs), firmwareNRPNPlumbing)
        XCTAssertEqual(Set(all.compactMap(\.ccNumber)).count, all.compactMap(\.ccNumber).count, "one row per CC")
    }

    func testProgramChanges() {
        XCTAssertEqual(Set(all.compactMap(\.programNumber)), Set(0..<80))
    }

    func testNRPNSetEqualsFirmware() {
        let ids = all.compactMap { c -> String? in
            if case .nrpn(let m, let p, _) = c.message { return "\(m)/\(p)" }
            return nil
        }
        XCTAssertEqual(Set(ids), firmwareNRPN)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testValueRules() {
        func hint(_ id: String) -> ValueHint { MIDICommandCatalog.command(id: id)!.valueHint }
        XCTAssertEqual(hint("cc.21"), .button)
        XCTAssertEqual(hint("cc.30"), .onOff)
        XCTAssertEqual(hint("cc.7"), .continuous)
        XCTAssertEqual(hint("cc.110"), .continuous)
        XCTAssertEqual(hint("cc.88"), .button)
        XCTAssertEqual(hint("cc.87"), .onOff)
        XCTAssertEqual(hint("nrpn.1.0"), .nrpnPercent)
        XCTAssertEqual(hint("nrpn.1.64"), .nrpnType)
        XCTAssertEqual(hint("nrpn.1.65"), .nrpnOnOff)
    }

    func testStockModuleOrderAndSetOrder() {
        let names = ["FX (DYN)", "AMP", "MOD", "DLY", "REV", "CAB", "DRIVE", "EQ"]
        for (n, name) in names.enumerated() {
            XCTAssertEqual(MIDICommandCatalog.command(id: "cc.\(20 + n)")!.title, "Toggle \(name)")
            XCTAssertEqual(MIDICommandCatalog.command(id: "cc.\(28 + n)")!.title, "Set \(name) on/off")
        }
    }

    func testNotImplementedAndNoEffect() {
        let ni = all.filter { $0.status == .notImplemented }.map(\.id).sorted()
        XCTAssertEqual(ni, ["nrpn.10.1", "nrpn.10.2"])
        XCTAssertTrue(all.filter { $0.status == .noEffect }.allSatisfy { c in
            if case .nrpn(let m, _, _) = c.message { return m <= 7 }
            return false
        })
        // CAB has 3 knobs: knobs 3, 4, 5 (both address ranges) are noEffect
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.5.3")!.status, .noEffect)
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.5.99")!.status, .noEffect)   // native knob 3 (0x63)
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.5.2")!.status, .implemented)
        XCTAssertTrue(MIDICommandCatalog.command(id: "nrpn.10.1")!.valueRule.contains("NOT IMPLEMENTED"))
    }

    func testNRPNExamplesEncodeLikeTheEditor() {
        // 0..7: percent in 14 bit; 8..10: raw D in CC 6 alone below 128
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.3.1")!.example, MIDIControl.nrpn(module: 3, param: 1, 50))
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.9.1")!.example, [0xB0, 99, 9, 0xB0, 98, 1, 0xB0, 6, 80])
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.10.7")!.example, MIDIControl.chainMoveMessage(slot: 2, to: 0))
    }

    func testModuleRowsUseSlotAndKnobNames() {
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.1.0")!.title, "AMP GAIN (knob 0)")
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.1.5")!.title, "AMP MASTER (knob 5)")
        XCTAssertTrue(MIDICommandCatalog.command(id: "nrpn.3.3")!.title.hasPrefix("DLY MOD / RELEASE"))
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.6.64")!.title, "DRIVE model")
        XCTAssertTrue(MIDICommandCatalog.command(id: "nrpn.6.64")!.notes.contains("0x25 FUZZ FACE"))
        XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.2.65")!.title, "MOD on/off")
    }

    func testGlobalCoversEveryParam() {
        let globals = MIDICommandCatalog.commands(in: .nrpnGlobal)
        XCTAssertEqual(globals.count, GlobalParam.allCases.count)
        for p in GlobalParam.allCases {
            let c = MIDICommandCatalog.command(id: "nrpn.8.\(p.rawValue)")!
            guard case .nrpnRaw(let range, let enc) = c.valueHint else { return XCTFail() }
            XCTAssertFalse(enc.isEmpty)
            if case .slider(let r) = p.spec.kind { XCTAssertEqual(range, r) }
            // the example D lies in the range
            XCTAssertTrue(range.contains(Int(c.example[8])), c.id)
        }
    }

    func testStompRowsMatchKeys() {
        for (i, key) in Stomp.keys.enumerated() {
            XCTAssertEqual(MIDICommandCatalog.command(id: "nrpn.10.\(3 + i)")!.title, "Stomp key \(key)")
        }
    }

    func testEveryGroupHasCommands() {
        for g in MIDICommandCatalog.groups { XCTAssertFalse(MIDICommandCatalog.commands(in: g).isEmpty, g.title) }
        XCTAssertEqual(MIDICommandCatalog.groups.count, 10)
        XCTAssertEqual(MIDICommandCatalog.commands(in: .nrpnModules).count, 8 * (2 + 12))
    }

    func testSearch() {
        let r = MIDICommandCatalog.filter("21")
        XCTAssertEqual(r.first?.id, "cc.21", "exact CC number first")
        XCTAssertEqual(MIDICommandCatalog.filter("").count, all.count)
        XCTAssertTrue(MIDICommandCatalog.filter("tuner").contains { $0.id == "cc.85" })
        XCTAssertTrue(MIDICommandCatalog.filter("AMP toggle").contains { $0.id == "cc.21" })
        XCTAssertTrue(MIDICommandCatalog.filter("cc 102").contains { $0.id == "cc.102" })
        XCTAssertTrue(MIDICommandCatalog.filter("zzzz-nothing").isEmpty)
        XCTAssertTrue(MIDICommandCatalog.filter("gain").contains { $0.id == "cc.102" })
        XCTAssertTrue(MIDICommandCatalog.search("P13").contains { $0.id == "pc.12" })
    }

    func testPlainText() {
        let text = MIDICommandCatalog.plainText()
        for cc in firmwareButtonAndValueCCs {
            XCTAssertTrue(text.contains("CC \(cc) "), "CC \(cc) missing from the export")
        }
        for cc in firmwareNRPNPlumbing { XCTAssertTrue(text.contains("CC \(cc)"), "plumbing CC \(cc) not explained") }
        XCTAssertTrue(text.contains("B0 15 7F"))
        XCTAssertTrue(text.contains(BLEMIDI.serviceUUID))
        for g in MIDICommandCatalog.groups { XCTAssertTrue(text.contains(g.title)) }
        XCTAssertTrue(text.contains("NOT IMPLEMENTED"))
        XCTAssertFalse(text.contains("CC 90 "))
        let line = MIDICommandCatalog.plainText(for: MIDICommandCatalog.command(id: "cc.21")!)
        XCTAssertEqual(line, "CC 21 | B0 15 7F | 176 21 127 | Toggle AMP | value >= 64 acts, below 64 is ignored")
    }

    func testGuide() {
        XCTAssertTrue(MIDIConnectionFacts.omniChannel)
        XCTAssertEqual(MIDIConnectionFacts.bleServiceUUID, "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
        XCTAssertEqual(MIDIConnectionFacts.bleCharacteristicUUID, "7772E5DB-3868-4112-A1A9-F2669D106BF3")
        XCTAssertTrue(MIDIConnectionFacts.sysExNote.contains("NOT needed"))
        XCTAssertFalse(MIDIPedalGuide.sections.isEmpty)
        XCTAssertTrue(MIDIPedalGuide.mappingTips.contains { $0.body.contains("CC 21") })
        XCTAssertTrue(MIDIPedalGuide.mappingTips.contains { $0.body.contains("CC 28..35") })
        XCTAssertTrue(MIDIPedalGuide.mappingTips.contains { $0.body.contains("CC 80") && $0.body.contains("CC 81") })
        XCTAssertEqual(Set((MIDIPedalGuide.sections + MIDIPedalGuide.mappingTips).map(\.id)).count, MIDIPedalGuide.sections.count + MIDIPedalGuide.mappingTips.count)
    }
}
