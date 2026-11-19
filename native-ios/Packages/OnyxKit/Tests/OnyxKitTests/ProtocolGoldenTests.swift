// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// SysEx / BLE-MIDI / MIDI control against vectors the original JavaScript produced (Tools/golden/gen_protocol.cjs).
final class ProtocolGoldenTests: XCTestCase {
    private struct HexIO: Decodable { let `in`: String; let out: String }
    private struct Build: Decodable { let cmd: UInt8; let payload: String; let frame: String? }
    private struct Parse: Decodable {
        struct Reply: Decodable { let type: UInt8; let data: String }
        let note: String; let frame: String; let isNull: Bool; let reply: Reply?
    }
    private struct Ble: Decodable { let msg: String; let chunk: Int; let ts: Int; let packets: [String] }
    private struct Unframe: Decodable { let note: String; let pushes: [String]; let frames: [[String]] }
    private struct CC: Decodable { let c: Int; let v: Int; let out: String }
    private struct PC: Decodable { let n: Int; let out: String }
    private struct NRPN: Decodable { let module: Int; let param: Int; let d: Int; let raw: Bool; let out: String }
    private struct Chain: Decodable { let order: [Int]; let slot: Int; let to: Int; let out: [Int] }
    private struct ChainMsg: Decodable { let slot: Int; let to: Int; let out: String }
    private struct Doc: Decodable {
        let pack: [HexIO]; let unpack: [HexIO]; let build: [Build]; let parse: [Parse]; let ble: [Ble]; let unframe: [Unframe]
        let cc: [CC]; let pc: [PC]; let nrpn: [NRPN]; let chain: [Chain]; let chainMsg: [ChainMsg]
    }

    private var doc: Doc!
    override func setUpWithError() throws { doc = try Fixtures.load("protocol") }

    func testPack8to7() {
        XCTAssertGreaterThan(doc.pack.count, 60)
        for v in doc.pack {
            let a = Fixtures.bytes(v.in)
            XCTAssertEqual(SysEx.pack8to7(a), Fixtures.bytes(v.out), "pack \(v.in)")
            XCTAssertEqual(Array(SysEx.unpack7to8(SysEx.pack8to7(a)).prefix(a.count)), a, "round trip \(v.in)")
        }
    }

    func testUnpack7to8() {
        XCTAssertGreaterThan(doc.unpack.count, 25)
        for v in doc.unpack { XCTAssertEqual(SysEx.unpack7to8(Fixtures.bytes(v.in)), Fixtures.bytes(v.out), "unpack \(v.in)") }
    }

    func testBuildFrame() {
        XCTAssertGreaterThan(doc.build.count, 80)
        var threw = 0
        for v in doc.build {
            let payload = Fixtures.bytes(v.payload)
            if let f = v.frame {
                XCTAssertEqual(try SysEx.buildFrame(cmd: v.cmd, payload: payload), Fixtures.bytes(f), "cmd \(v.cmd) payload \(v.payload)")
            } else {
                threw += 1
                XCTAssertThrowsError(try SysEx.buildFrame(cmd: v.cmd, payload: payload))
            }
        }
        XCTAssertEqual(threw, 3)
        XCTAssertEqual(try SysEx.buildFrame(cmd: 5), try SysEx.buildFrame(cmd: 5, payload: []))
    }

    func testParseReply() {
        XCTAssertGreaterThan(doc.parse.count, 180)
        var valid = 0, rejected = 0
        for v in doc.parse {
            let got = SysEx.parseReply(Fixtures.bytes(v.frame))
            if let e = v.reply {
                valid += 1
                XCTAssertEqual(got, SysEx.Reply(type: e.type, data: Fixtures.bytes(e.data)), "\(v.note) \(v.frame)")
            } else {
                rejected += 1
                XCTAssertNil(got, "\(v.note) \(v.frame)")
            }
        }
        XCTAssertGreaterThan(valid, 60)
        XCTAssertGreaterThan(rejected, 60)
    }

    func testBuildThenParse() throws {
        for n in [0, 1, 7, 164, 256] {
            let p = (0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
            XCTAssertEqual(SysEx.parseReply(try SysEx.buildFrame(cmd: 0x63, payload: p)), SysEx.Reply(type: 0x63, data: p))
        }
    }

    func testBLEFrames() {
        XCTAssertGreaterThan(doc.ble.count, 150)
        for v in doc.ble {
            let got = BLEMIDI.frames(Fixtures.bytes(v.msg), chunkMax: v.chunk, timestamp: v.ts)
            XCTAssertEqual(got, v.packets.map(Fixtures.bytes), "msg \(v.msg) chunk \(v.chunk) ts \(v.ts)")
            XCTAssertTrue(got.allSatisfy { $0.count <= v.chunk || Fixtures.bytes(v.msg).first != 0xF0 })
        }
    }

    func testBLEUnframer() {
        XCTAssertGreaterThan(doc.unframe.count, 100)
        var produced = 0
        for sc in doc.unframe {
            var u = BLEMIDI.Unframer()
            for (i, p) in sc.pushes.enumerated() {
                let got = u.push(Fixtures.bytes(p))
                produced += got.count
                XCTAssertEqual(got, sc.frames[i].map(Fixtures.bytes), "\(sc.note) push \(i): \(p)")
            }
        }
        XCTAssertGreaterThan(produced, 50)
    }

    func testBLEUnframerReset() {
        var u = BLEMIDI.Unframer()
        XCTAssertEqual(u.push([0x80, 0xF0, 0x01]), [])
        u.reset()
        XCTAssertEqual(u.push([0x80, 0x02, 0xF7]), [])
    }

    func testControlChange() {
        for v in doc.cc { XCTAssertEqual(MIDIControl.cc(v.c, v.v), Fixtures.bytes(v.out), "cc \(v.c) \(v.v)") }
        for v in doc.pc { XCTAssertEqual(MIDIControl.pc(v.n), Fixtures.bytes(v.out), "pc \(v.n)") }
    }

    func testNRPN() {
        XCTAssertGreaterThan(doc.nrpn.count, 800)
        for v in doc.nrpn {
            XCTAssertEqual(MIDIControl.nrpn(module: v.module, param: v.param, v.d, raw: v.raw), Fixtures.bytes(v.out), "nrpn \(v.module) \(v.param) \(v.d) raw \(v.raw)")
            if !v.raw { XCTAssertEqual(MIDIControl.nrpn(module: v.module, param: v.param, v.d), Fixtures.bytes(v.out)) }
        }
    }

    func testChainMove() {
        XCTAssertGreaterThan(doc.chain.count, 1500)
        for v in doc.chain { XCTAssertEqual(MIDIControl.chainMove(v.order, slot: v.slot, to: v.to), v.out, "\(v.order) slot \(v.slot) to \(v.to)") }
        XCTAssertEqual(doc.chainMsg.count, 64)
        for v in doc.chainMsg { XCTAssertEqual(MIDIControl.chainMoveMessage(slot: v.slot, to: v.to), Fixtures.bytes(v.out), "slot \(v.slot) to \(v.to)") }
    }

    func testSlotModuleTable() {
        XCTAssertEqual(Slot.allCases.map(\.module), [0, 6, 1, 5, 7, 2, 3, 4])
    }
}
