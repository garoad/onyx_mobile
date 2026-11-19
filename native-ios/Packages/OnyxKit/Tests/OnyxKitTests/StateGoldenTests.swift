// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// `DeviceState.decode` against `decodeState` of the original JavaScript (Tools/golden/gen_protocol.cjs).
final class StateGoldenTests: XCTestCase {
    private struct JSSlot: Decodable { let on: Bool; let rawOn: Int; let type: Int; let knobs: [Int] }
    private struct JSGlobals: Decodable {
        let inGain, gate, outType, cabLine, limiter, fizz, width, routing, balance, geq: Int
        let bands: [Int]
        let tunerRef, tunerMute, loopback, usbMode, bpm, pattern, gVol, drums: Int
    }
    private struct JSState: Decodable {
        let view, preset, flags, presetVol, outLevel: Int
        let name: String
        let slots: [JSSlot]
        let g: JSGlobals
        let stomp: [Int]
        let namCount: Int
        let userCab: Bool
        let cabCount, namFree, cabFree: Int
        let order: [Int]
    }
    private struct Case: Decodable { let note: String; let record: String; let state: JSState? }

    func testDecodeMatchesJS() throws {
        let cases: [Case] = try Fixtures.load("state")
        XCTAssertGreaterThan(cases.count, 150)
        var decoded = 0, rejected = 0, customOrder = 0, defaultOrder = 0
        for c in cases {
            let rec = Fixtures.bytes(c.record)
            let got = DeviceState.decode(rec)
            guard let e = c.state else { rejected += 1; XCTAssertNil(got, c.note); continue }
            guard let s = got else { XCTFail("nil for \(c.note) \(c.record)"); continue }
            decoded += 1
            let ctx = "\(c.note) \(c.record)"
            XCTAssertEqual(Array(s.name.unicodeScalars.map(\.value)), Array(e.name.unicodeScalars.map(\.value)), "name: \(ctx)")
            XCTAssertEqual([s.view, s.preset, s.flags, s.presetVol, s.outLevel], [e.view, e.preset, e.flags, e.presetVol, e.outLevel], ctx)
            XCTAssertEqual(s.slots.count, 8, ctx)
            for (i, js) in e.slots.enumerated() {
                XCTAssertEqual(s.slots[i], DeviceState.SlotState(on: js.on, type: js.type, knobs: js.knobs), "slot \(i): \(ctx)")
            }
            let g = e.g
            XCTAssertEqual(s.g, DeviceState.Globals(
                inGain: g.inGain, gate: g.gate, outType: g.outType, cabLine: g.cabLine, limiter: g.limiter, fizz: g.fizz, width: g.width,
                routing: g.routing, balance: g.balance, geq: g.geq, bands: g.bands, tunerRef: g.tunerRef, tunerMute: g.tunerMute,
                loopback: g.loopback, usbMode: g.usbMode, bpm: g.bpm, pattern: g.pattern, gVol: g.gVol, drums: g.drums), "globals: \(ctx)")
            XCTAssertEqual(s.stomp, e.stomp, ctx)
            XCTAssertEqual([s.namCount, s.cabCount, s.namFree, s.cabFree], [e.namCount, e.cabCount, e.namFree, e.cabFree], ctx)
            XCTAssertEqual(s.userCab, e.userCab, ctx)
            XCTAssertEqual(s.order, e.order, "order: \(ctx)")
            if e.order == Array(0..<8) { defaultOrder += 1 } else { customOrder += 1 }
            XCTAssertEqual(s.isStompMode, e.flags & 1 != 0)
            XCTAssertEqual(s.tunerOpen, e.flags & 2 != 0)
            XCTAssertEqual(s.groovePlaying, e.flags & 4 != 0)
        }
        XCTAssertGreaterThan(decoded, 140)
        XCTAssertGreaterThanOrEqual(rejected, 8)
        XCTAssertGreaterThan(customOrder, 30)
        XCTAssertGreaterThan(defaultOrder, 5)
    }

    func testRejectsShortAndWrongVersion() {
        XCTAssertNil(DeviceState.decode([]))
        XCTAssertNil(DeviceState.decode([UInt8](repeating: 1, count: 116)))
        var r = [UInt8](repeating: 0, count: 128)
        XCTAssertNil(DeviceState.decode(r))
        r[0] = 1
        XCTAssertNotNil(DeviceState.decode(r))
        r[0] = 2
        XCTAssertNil(DeviceState.decode(r))
    }
}
