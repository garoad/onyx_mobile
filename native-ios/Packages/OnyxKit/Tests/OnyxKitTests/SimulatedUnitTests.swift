// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// Drives the unit with raw frames and messages, the way the firmware's own host tests do.
@MainActor
final class SimulatedUnitTests: XCTestCase {
    private var replies: [SysEx.Reply] = []

    private func makeUnit() -> SimulatedUnit {
        replies = []
        let u = SimulatedUnit(isBLE: false)
        u.onFrame = { [unowned self] f in if let r = SysEx.parseReply(f) { replies.append(r) } }
        return u
    }

    private func ask(_ u: SimulatedUnit, _ cmd: UInt8, _ p: [UInt8] = []) async throws -> SysEx.Reply {
        replies = []
        try await u.send(frame: SysEx.buildFrame(cmd: cmd, payload: p))
        return try XCTUnwrap(replies.last)
    }

    private func readBack(_ u: SimulatedUnit, _ i: UInt8) async throws -> PresetRecord {
        let r = try await ask(u, 83, [i])
        return try XCTUnwrap(PresetRecord(record: Array(r.data[2...])))
    }

    private func send(_ u: SimulatedUnit, _ m: [UInt8]) async throws {
        for i in stride(from: 0, to: m.count, by: 3) { try await u.send(message: Array(m[i..<min(i + 3, m.count)])) }
    }

    private func state(_ u: SimulatedUnit) async throws -> DeviceState {
        let r = try await ask(u, 80)
        XCTAssertEqual(r.type, 0x60)
        XCTAssertEqual(r.data.count, 128)
        return try XCTUnwrap(DeviceState.decode(r.data))
    }

    func testStateRecordRoundTrips() async throws {
        let u = makeUnit()
        let s = try await state(u)
        XCTAssertEqual(s, u.live)
        XCTAssertEqual(s.preset, 0)
        XCTAssertEqual(s.name, "Clean Sparkle")
        XCTAssertEqual(s.order, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(s.namCount, 2)
        XCTAssertEqual(s.cabCount, 1)
        XCTAssertEqual(s.namFree, 14)
        XCTAssertEqual(s.cabFree, 14)
        XCTAssertFalse(s.isStompMode)
    }

    func testNamesPagesAndBuildCode() async throws {
        let u = makeUnit()
        var total = 1, start = 0, all: [String] = [], first = 0
        while start < total {
            let d = try await ask(u, 81, [0, UInt8(start)])
            XCTAssertEqual(d.type, 0x61)
            total = Int(d.data[1]); first = Int(d.data[4])
            let n = Int(d.data[3])
            XCTAssertLessThanOrEqual(n, 15)
            for i in 0..<n { all.append(String(decoding: d.data[(5 + i * 16)..<(21 + i * 16)].filter { $0 != 0 }, as: UTF8.self)) }
            start += n
        }
        XCTAssertEqual(first, 20)
        XCTAssertEqual(all.count, 22)
        XCTAssertEqual(all[0], "1 UK Clean")
        XCTAssertEqual(all[19], "20 Euro Clean B", "a name field is 16 bytes, NUL terminated")
        XCTAssertEqual(all[20], "Fender NAM")
        let cabs = try await ask(u, 81, [1, 0])
        XCTAssertEqual(cabs.data[1], 21)
        let b = try await ask(u, 81, [255, 0])
        XCTAssertEqual(String(decoding: b.data[5..<(5 + Int(b.data[3]))], as: UTF8.self), u.buildCode)
    }

    func testUserOpRenameAndDelete() async throws {
        let u = makeUnit()
        var r = try await ask(u, 82, [1, 0, 1] + Array("Marshall".utf8))
        XCTAssertEqual(r.type, 0x62)
        XCTAssertEqual(r.data, [1, 0, 1, 0])
        XCTAssertEqual(u.typeNames(kind: 0)[21], "Marshall")
        r = try await ask(u, 82, [0, 0, 0])
        XCTAssertEqual(r.data, [0, 0, 0, 0])
        XCTAssertEqual(u.typeNames(kind: 0)[20], "", "a deleted capture keeps its number and has an empty name")
        r = try await ask(u, 82, [0, 0, 9])
        XCTAssertNotEqual(r.data[3], 0, "deleting a capture that does not exist fails")
        r = try await ask(u, 82, [2, 1, 0])
        XCTAssertEqual(r.data[3], 0)
        XCTAssertEqual(u.typeNames(kind: 1).count, 20)
    }

    func testPresetReadAndOutOfRange() async throws {
        let u = makeUnit()
        var r = try await ask(u, 83, [0])
        XCTAssertEqual(r.type, 0x63)
        XCTAssertEqual(r.data[1], 0)
        let p = try XCTUnwrap(PresetRecord(record: Array(r.data[2...])))
        XCTAssertEqual(p.name, "Clean Sparkle")
        XCTAssertEqual(p.seq, 1)
        XCTAssertFalse(p.isEmpty)
        r = try await ask(u, 83, [40])
        let e = try XCTUnwrap(PresetRecord(record: Array(r.data[2...])))
        XCTAssertTrue(e.isEmpty)
        XCTAssertEqual(e.name, "EMPTY")
        r = try await ask(u, 83, [80])
        XCTAssertEqual(r.data[1], 1)
        XCTAssertTrue(r.data[2...].allSatisfy { $0 == 0 })
    }

    private func upload(_ u: SimulatedUnit, _ bytes: [UInt8], target: UInt8, slot: UInt8) async throws -> SysEx.Reply {
        _ = try await ask(u, 25, [UInt8(bytes.count & 255), UInt8(bytes.count >> 8), 0, target, slot])
        var last = try XCTUnwrap(replies.last)
        for i in stride(from: 0, to: bytes.count, by: 100) { last = try await ask(u, 34, Array(bytes[i..<min(i + 100, bytes.count)])) }
        return last
    }

    func testUploadTarget0SavesAndTarget4Restores() async throws {
        let u = makeUnit()
        var rec = SimulatedFactory.record(0)
        rec.name = "Saved"
        rec.seq = 777
        var ack = try await upload(u, rec.encode(), target: 0, slot: 50)
        XCTAssertEqual(ack.type, 0x64)
        XCTAssertEqual(ack.data, [164, 0, 0, 1])
        var back = try await readBack(u, 50)
        XCTAssertEqual(back.name, "Saved")
        XCTAssertEqual(back.seq, 2, "pa_preset_save: the slot's own seq + 1, not the record's")
        XCTAssertFalse(back.isEmpty)

        var empty = SimulatedFactory.record(60)
        empty.seq = 9
        ack = try await upload(u, empty.encode(), target: 4, slot: 51)
        XCTAssertEqual(ack.data[3], 1)
        back = try await readBack(u, 51)
        XCTAssertEqual(back, empty, "restore keeps seq and the EMPTY flag")
    }

    func testBadRecordIsRefusedAndALateChunkSaysHow() async throws {
        let u = makeUnit()
        var bytes = SimulatedFactory.record(1).encode()
        bytes[20] ^= 0xFF
        var ack = try await upload(u, bytes, target: 0, slot: 60)
        XCTAssertEqual(ack.data[3], 2)
        XCTAssertTrue(u.presets[60].isEmpty)
        ack = try await ask(u, 34, [])
        XCTAssertEqual(ack.data[3], 2, "a chunk after a refused transfer: refused")
        let fresh = makeUnit()
        ack = try await ask(fresh, 34, [])
        XCTAssertEqual(ack.data[3], 3, "no transfer open")
    }

    func testBeginOverTheBufferIsRefused() async throws {
        let u = makeUnit()
        let r = try await ask(u, 25, [0x01, 0x80, 0x00, 0, 0])      // 32769 bytes
        XCTAssertEqual(r.data[3], 2)
    }

    func testDroppedChunkLeavesTheTransferOpen() async throws {
        let u = makeUnit()
        let bytes = SimulatedFactory.record(2).encode()
        _ = try await ask(u, 25, [164, 0, 0, 0, 55])
        u.dropIncomingChunks = 1
        replies = []
        try await u.send(frame: SysEx.buildFrame(cmd: 34, payload: Array(bytes[0..<100])))
        XCTAssertTrue(replies.isEmpty)
        var ack = try await ask(u, 34, [])
        XCTAssertEqual(ack.data, [0, 0, 0, 0])
        ack = try await ask(u, 34, Array(bytes[0..<100]))
        XCTAssertEqual(ack.data, [100, 0, 0, 0])
        ack = try await ask(u, 34, Array(bytes[100...]))
        XCTAssertEqual(ack.data, [164, 0, 0, 1])
    }

    func testLegacyCommitByCmd48() async throws {
        let u = makeUnit()
        u.acknowledgesUploads = false
        let bytes = SimulatedFactory.record(3).encode()
        for f in try OnyxSession.uploadFrames(bytes, target: 0, slot: 70, chunk: 100) { try await u.send(frame: f) }
        XCTAssertFalse(u.presets[70].isEmpty)
        XCTAssertEqual(u.presets[70].name, SimulatedFactory.record(3).name)
    }

    func testFlashReadIsRefusedOutOfRange() async throws {
        let u = makeUnit()
        var r = try await ask(u, 84, [0, 0, 0, 0, 16])
        XCTAssertEqual(r.type, 0x65)
        XCTAssertEqual(r.data[5], 0)
        XCTAssertEqual(r.data.count, 6 + 16)
        r = try await ask(u, 84, [0, 0, 0x20, 0, 16])
        XCTAssertEqual(r.data[5], 1)
        XCTAssertEqual(r.data.count, 6)
    }

    func testProgramChangeAndStepping() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.pc(9))
        var s = try await state(u)
        XCTAssertEqual(s.preset, 9)
        XCTAssertEqual(s.name, u.presets[9].name)
        try await send(u, MIDIControl.cc(81, 127))
        XCTAssertEqual(u.live.preset, 8)
        try await send(u, MIDIControl.cc(81, 10))
        XCTAssertEqual(u.live.preset, 8, "a value below 64 does nothing")
        try await send(u, MIDIControl.pc(0)); try await send(u, MIDIControl.cc(81, 127))
        XCTAssertEqual(u.live.preset, 79, "wraps")
        try await send(u, MIDIControl.cc(80, 127))
        s = try await state(u)
        XCTAssertEqual(s.preset, 0)
        try await send(u, MIDIControl.pc(80))
        XCTAssertEqual(u.live.preset, 0, "PC 80 is out of range")
    }

    func testModuleSwitchesAndToggles() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.cc(28 + Slot.rev.module, 127))
        XCTAssertTrue(u.live.slots[Slot.rev.rawValue].on)
        try await send(u, MIDIControl.cc(28 + Slot.rev.module, 0))
        XCTAssertFalse(u.live.slots[Slot.rev.rawValue].on)
        let amp = u.live.slots[Slot.amp.rawValue].on
        try await send(u, MIDIControl.cc(21, 127))          // the stock foot controller's AMP toggle
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].on, !amp)
        try await send(u, MIDIControl.cc(21, 20))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].on, !amp)
    }

    func testNRPNKnobsTypesAndEnable() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.nrpn(module: 1, param: 0x60, 73))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[0], 73)
        try await send(u, MIDIControl.nrpn(module: 5, param: 2, 0))
        XCTAssertEqual(u.live.slots[Slot.cab.rawValue].knobs[2], 0)
        try await send(u, MIDIControl.nrpn(module: 3, param: 0x65, 100))
        XCTAssertEqual(u.live.slots[Slot.dly.rawValue].knobs[5], 100)
        try await send(u, MIDIControl.nrpn(module: 1, param: 0x40, 7 + 0x20, raw: true))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].type, 7)
        try await send(u, MIDIControl.nrpn(module: 1, param: 0x40, 21 + 0x20, raw: true))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].type, 21, "a stored capture")
        try await send(u, MIDIControl.nrpn(module: 1, param: 0x40, 40 + 0x20, raw: true))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].type, 21, "a type that does not exist is ignored")
        try await send(u, MIDIControl.nrpn(module: 4, param: 0x41, 127, raw: true))
        XCTAssertTrue(u.live.slots[Slot.rev.rawValue].on)
        try await send(u, MIDIControl.nrpn(module: 4, param: 0x41, 0, raw: true))
        XCTAssertFalse(u.live.slots[Slot.rev.rawValue].on)
    }

    func testRPNNullClearsTheSelection() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.cc(99, 1) + MIDIControl.cc(98, 0x60) + MIDIControl.cc(101, 127) + MIDIControl.cc(100, 127))
        try await send(u, MIDIControl.cc(6, 10) + MIDIControl.cc(38, 3))
        XCTAssertNotEqual(u.live.slots[Slot.amp.rawValue].knobs[0], 8)
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[0], PresetRecord.percent(q16: u.presets[0].params[2][0]))
    }

    func testDirectCCsAndPresetVolume() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.cc(7, 127)); XCTAssertEqual(u.live.presetVol, 100)
        try await send(u, MIDIControl.cc(7, 64)); XCTAssertEqual(u.live.presetVol, 50)
        try await send(u, MIDIControl.cc(102, 64)); XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[0], 50)
        try await send(u, MIDIControl.cc(103, 127)); XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[5], 100)
        try await send(u, MIDIControl.cc(118, 0)); XCTAssertEqual(u.live.slots[Slot.cab.rawValue].knobs[2], 0)
        try await send(u, MIDIControl.cc(115, 127)); XCTAssertEqual(u.live.slots[Slot.mod.rawValue].knobs[1], 100)
    }

    func testGlobalsGrooveAndStomp() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.nrpn(module: 8, param: 0, 20, raw: true)); XCTAssertEqual(u.live.g.inGain, 8)
        try await send(u, MIDIControl.nrpn(module: 8, param: 2, 33, raw: true)); XCTAssertEqual(u.live.outLevel, 33)
        try await send(u, MIDIControl.nrpn(module: 8, param: 19, 2, raw: true))
        XCTAssertEqual(u.live.g.usbMode, 2)
        let st = try await state(u)
        XCTAssertEqual(st.g.usbMode, 2, "USB mode travels in the flags")
        try await send(u, MIDIControl.nrpn(module: 8, param: 18, 0, raw: true)); XCTAssertEqual(u.live.g.loopback, 0)
        try await send(u, MIDIControl.nrpn(module: 9, param: 1, 260 - 40, raw: true)); XCTAssertEqual(u.live.g.bpm, 260)
        try await send(u, MIDIControl.nrpn(module: 9, param: 2, 7, raw: true)); XCTAssertEqual(u.live.g.pattern, 7)
        try await send(u, MIDIControl.cc(86, 127)); XCTAssertTrue(u.live.groovePlaying)
        try await send(u, MIDIControl.cc(86, 0)); XCTAssertFalse(u.live.groovePlaying)
        try await send(u, MIDIControl.cc(85, 127)); XCTAssertTrue(u.live.tunerOpen)
        try await send(u, MIDIControl.cc(87, 127)); XCTAssertTrue(u.live.isStompMode)
        try await send(u, MIDIControl.nrpn(module: 10, param: 3, 4, raw: true))      // VOL- = module 4 = REV
        XCTAssertEqual(u.live.stomp[0], Slot.rev.rawValue)
        try await send(u, MIDIControl.nrpn(module: 10, param: 0, 41, raw: true)); XCTAssertEqual(u.live.presetVol, 41)
    }

    func testChainMove() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.chainMoveMessage(slot: Slot.rev.rawValue, to: 0))
        XCTAssertEqual(u.live.order, [7, 0, 1, 2, 3, 4, 5, 6])
        let st = try await state(u)
        XCTAssertEqual(st.order, [7, 0, 1, 2, 3, 4, 5, 6])
    }

    func testSaveCurrentWritesTheLiveSoundIntoThePreset() async throws {
        let u = makeUnit()
        try await send(u, MIDIControl.pc(5))
        try await send(u, MIDIControl.nrpn(module: 1, param: 0x60, 11))
        XCTAssertNotEqual(PresetRecord.percent(q16: u.presets[5].params[2][0]), 11)
        try await send(u, MIDIControl.cc(88, 10))
        XCTAssertEqual(u.presets[5].seq, 1, "CC 88 below 64 does nothing")
        try await send(u, MIDIControl.cc(88, 127))
        XCTAssertEqual(PresetRecord.percent(q16: u.presets[5].params[2][0]), 11)
        XCTAssertEqual(u.presets[5].seq, 2)
        try await send(u, MIDIControl.pc(6)); try await send(u, MIDIControl.pc(5))
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[0], 11)
    }

    func testEdgeFactoryBank() {
        let u = makeUnit()
        XCTAssertEqual(u.presets.count, 80)
        XCTAssertTrue(u.presets[..<40].allSatisfy { !$0.isEmpty && $0.seq == 1 })
        XCTAssertTrue(u.presets[40...].allSatisfy { $0.isEmpty && $0.name == "EMPTY" && $0.seq == 1 })
        XCTAssertEqual(Set(u.presets[..<40].map(\.name)).count, 40)
        XCTAssertTrue(u.presets.allSatisfy { PresetRecord.isValid($0.encode()) })
        XCTAssertTrue(u.presets[..<40].allSatisfy { $0.slotType[2] < 20 && $0.slotType[3] < 20 })
    }

    func testSilentUnitAnswersNothing() async throws {
        let u = makeUnit()
        u.isSilent = true
        replies = []
        try await u.send(frame: SysEx.buildFrame(cmd: 80))
        XCTAssertTrue(replies.isEmpty)
    }
}
