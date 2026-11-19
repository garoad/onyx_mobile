// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// A Pocket AMP in memory: the same SysEx commands, upload acknowledgements and channel messages as the firmware (reference/firmware/sysex.c,
/// usb_ble.c, reference/MIDI-MAP-CUSTOM.md), so the app runs in the simulator and the session logic can be tested without hardware.
///
/// Replies are delivered synchronously from inside `send(frame:)`; the session installs its waiter before it sends.
@MainActor
public final class SimulatedUnit: OnyxTransport {
    public let displayName: String
    public let isBLE: Bool
    public let uploadChunk: Int
    public var onFrame: (([UInt8]) -> Void)?
    public var onClose: (() -> Void)?

    // Test knobs.
    /// The unit hears everything and answers nothing.
    public var isSilent = false
    /// The next n cmd 34 chunks that carry data are lost on the way: no effect, no acknowledgement (the MIDI receive ring overflowing).
    public var dropIncomingChunks = 0
    /// The next n upload begins are answered with state 2 (the audio core still holds a swap).
    public var refuseBegins = 0
    /// False imitates an older firmware: uploads are taken, but cmd 25 / 34 are not answered with 0x64 (the editor then falls back to blind frames).
    public var acknowledgesUploads = true
    public private(set) var receivedMessages: [[UInt8]] = []
    public private(set) var receivedCommands: [UInt8] = []

    // The unit.
    public private(set) var presets: [PresetRecord]
    public internal(set) var live: DeviceState
    public private(set) var captures: [String?]
    public private(set) var cabinets: [String?]
    public let buildCode = "SIM-1.0"
    private var btMode = 1, brightness = 80, homeView = 0

    static let captureSlots = 16, cabinetSlots = 15, firstUser = 20, uploadBufferSize = 32768
    private static let namesPerPage = 15

    // NRPN selection (usb_ble.c).
    private var nrpnMod = 0, nrpnPar = 0, haveMod = false, havePar = false, haveHi = false, nrpnHi = 0

    // The upload session (pa_upload_session_t).
    private var upArmed = false, upTarget: UInt8 = 0, upSlot: UInt8 = 0, upDeclared = 0, upRx = 0
    private var upBuffer: [UInt8] = []
    private var upResult: UInt8 = 0     // 0 none yet, 1 stored, 2 refused

    public init(name: String = "Pocket AMP (simulated)", isBLE: Bool = true, uploadChunk: Int? = nil) {
        displayName = name
        self.isBLE = isBLE
        self.uploadChunk = uploadChunk ?? (isBLE ? 100 : 200)
        presets = (0..<PresetRecord.count).map(SimulatedFactory.record)
        captures = [String?](repeating: nil, count: Self.captureSlots)
        cabinets = [String?](repeating: nil, count: Self.cabinetSlots)
        captures[0] = "Fender NAM"; captures[1] = "Plexi NAM"; cabinets[0] = "Greenback IR"
        let slots = (0..<8).map { _ in DeviceState.SlotState(on: false, type: 0, knobs: [Int](repeating: 50, count: 6)) }
        let g = DeviceState.Globals(inGain: 0, gate: -80, outType: 0, cabLine: 1, limiter: 0, fizz: 0, width: 100, routing: 0, balance: 0, geq: 0,
                                    bands: [0, 0, 0, 0, 0], tunerRef: 440, tunerMute: 0, loopback: 1, usbMode: 0, bpm: 120, pattern: 0, gVol: 70, drums: 1)
        live = DeviceState(view: 0, preset: 0, flags: 0x18, presetVol: 70, outLevel: 80, name: "", slots: slots, g: g, stomp: [1, 5, 6, 7],
                           namCount: 0, userCab: false, cabCount: 0, namFree: 0, cabFree: 0, order: [0, 1, 2, 3, 4, 5, 6, 7])
        loadPreset(0)
        syncCounts()
    }

    /// The capture / cabinet counts of the state record.
    private func syncCounts() {
        let nam = captures.compactMap { $0 }.count, cab = cabinets.compactMap { $0 }.count
        live.namCount = nam; live.cabCount = cab
        live.namFree = Self.captureSlots - nam; live.cabFree = Self.cabinetSlots - cab
    }

    // MARK: Test hooks

    /// The peer went away (Bluetooth switched off, cable pulled).
    public func simulateDisconnect() { onClose?() }

    /// Type numbers of the amp (kind 0) or cabinet (kind 1) list: 20 stock, then the stored user items up to the last one that exists.
    public func typeNames(kind: Int) -> [String] {
        let stock = kind == 0 ? SimulatedFactory.stockAmps : SimulatedFactory.stockCabs
        let user = kind == 0 ? captures : cabinets
        let used = (user.lastIndex { $0 != nil } ?? -1) + 1
        return stock + user.prefix(used).map { $0 ?? "" }
    }

    // MARK: OnyxTransport

    public func send(message: [UInt8]) async throws {
        receivedMessages.append(message)
        if !isSilent { handle(message: message) }
    }

    public func send(frame: [UInt8]) async throws {
        guard let r = SysEx.parseReply(frame) else { return }       // a frame with a wrong checksum is dropped (frames_err)
        receivedCommands.append(r.type)
        if !isSilent { dispatch(cmd: r.type, payload: r.data) }
    }

    public func close() {}

    private func reply(_ type: UInt8, _ data: [UInt8]) {
        // data is never over 256 bytes: the largest reply is the names page, 5 + 15 * 16.
        if let f = try? SysEx.buildFrame(cmd: type, payload: data) { onFrame?(f) }
    }

    // MARK: SysEx

    private func dispatch(cmd: UInt8, payload p: [UInt8]) {
        let len = p.count
        if cmd == 25 {
            if len >= 3 {
                if refuseBegins > 0 { refuseBegins -= 1; upResult = 2; upAck(2); return }
                upDeclared = Int(p[0]) | Int(p[1]) << 8 | Int(p[2]) << 16
                upTarget = len > 3 ? p[3] : 1
                upSlot = len > 4 ? p[4] : 0
                upBuffer = []; upRx = 0; upResult = 0
                upArmed = upDeclared != 0 && upDeclared <= Self.uploadBufferSize
                if !upArmed { upResult = 2; upAck(2); return }
                if len > 5 {
                    upBuffer = Array(p[5...].prefix(Self.uploadBufferSize)); upRx = upBuffer.count
                    if upRx >= upDeclared { commitUpload() }
                }
                upAck(upArmed ? 0 : (upResult == 1 ? 1 : 2))
            }
        } else if cmd == 48 && upArmed {
            commitUpload()
        } else if cmd == 80 {
            reply(0x60, stateRecord())
        } else if cmd == 84 {
            flashRead(p)
        } else if cmd == 83 {
            let idx = len > 0 ? Int(p[0]) : 0xFF
            var out = [UInt8](repeating: 0, count: 2 + PresetRecord.size)
            out[0] = UInt8(truncatingIfNeeded: idx)
            if idx < PresetRecord.count { out.replaceSubrange(2..., with: presets[idx].encode()) } else { out[1] = 1 }
            reply(0x63, out)
        } else if cmd == 81 {
            names(kind: len > 0 ? Int(p[0]) : 0, start: len > 1 ? Int(p[1]) : 0)
        } else if cmd == 82 {
            userOp(p)
        } else if cmd == 34 && !upArmed {
            upAck(upResult == 1 ? 1 : (upResult == 2 ? 2 : 3))      // a late or repeated chunk: say how the transfer ended
        } else if cmd == 34 && upArmed {
            if len > 0 && dropIncomingChunks > 0 { dropIncomingChunks -= 1; return }
            if len > 0 {
                let chunk = min(len, max(0, upDeclared - upRx))
                if upRx + chunk <= Self.uploadBufferSize { upBuffer += p.prefix(chunk); upRx += chunk }
                if upRx >= upDeclared { commitUpload() }
            }
            upAck(upArmed ? 0 : (upResult == 1 ? 1 : 2))
        }
    }

    private func upAck(_ state: UInt8) {
        guard acknowledgesUploads else { return }
        reply(0x64, [UInt8(upRx & 0xFF), UInt8((upRx >> 8) & 0xFF), UInt8((upRx >> 16) & 0xFF), state])
    }

    private func commitUpload() {
        upArmed = false
        guard upRx == upDeclared else { upResult = 2; return }
        var ok = false
        switch upTarget {
        case 0, 4:
            let rec = Array(upBuffer.prefix(PresetRecord.size))
            if upRx >= PresetRecord.size, Int(upSlot) < PresetRecord.count, let r = PresetRecord(record: rec) {
                if upTarget == 0 { savePreset(Int(upSlot), r) } else { presets[Int(upSlot)] = r }       // pa_preset_save / pa_preset_restore
                ok = true
            }
        case 1:
            let slot = upSlot == 0xFF ? captures.firstIndex { $0 == nil } : Int(upSlot)
            if let s = slot, s < Self.captureSlots { captures[s] = String(format: "USER NAM %02d", s + 1); ok = true }
        case 2:
            let taps = upRx / 4
            if upRx & 3 == 0, (16...1024).contains(taps) {
                if upSlot == 0xFE { live.userCab = true; ok = true }
                else if let s = upSlot == 0xFF ? cabinets.firstIndex(where: { $0 == nil }) : Int(upSlot), s < Self.cabinetSlots {
                    cabinets[s] = String(format: "CAB %02d", s + 1); ok = true
                }
            }
        default: break
        }
        upResult = ok ? 1 : 2
        syncCounts()
    }

    private func names(kind: Int, start: Int) {
        if kind == 255 {
            let code = Array(buildCode.utf8)
            reply(0x61, [255, 1, 0, UInt8(code.count), 0] + code)
            return
        }
        guard kind <= 1 else { return }
        let list = typeNames(kind: kind)
        let n = max(0, min(Self.namesPerPage, list.count - start))
        var out: [UInt8] = [UInt8(kind), UInt8(list.count), UInt8(start), UInt8(n), UInt8(Self.firstUser)]
        for i in 0..<n {
            var f = [UInt8](repeating: 0, count: 16)
            for (j, u) in list[start + i].unicodeScalars.prefix(15).enumerated() { f[j] = UInt8(truncatingIfNeeded: u.value) }
            out += f
        }
        reply(0x61, out)
    }

    private func userOp(_ p: [UInt8]) {
        let op = p.first ?? 0xFF, kind = p.count > 1 ? p[1] : 0xFF, idx = p.count > 2 ? Int(p[2]) : 0xFF
        var rc = -1
        let slots = kind == 0 ? captures.count : cabinets.count
        func active(_ i: Int) -> Bool { i < slots && (kind == 0 ? captures[i] != nil : cabinets[i] != nil) }
        func set(_ i: Int, _ v: String?) { if kind == 0 { captures[i] = v } else { cabinets[i] = v } }
        if op == 2 && kind <= 1 {
            (0..<slots).forEach { set($0, nil) }; rc = 0
        } else if kind <= 1 && op == 0 && active(idx) {
            set(idx, nil); rc = 0
        } else if kind <= 1 && op == 1 && p.count > 3 && p.count < 3 + 24 && active(idx) {
            let nm = String(String.UnicodeScalarView(p[3...].prefix { $0 != 0 }.map { Unicode.Scalar($0) }))
            if !nm.isEmpty { set(idx, nm); rc = 0 }
        }
        syncCounts()
        reply(0x62, [op, kind, UInt8(truncatingIfNeeded: idx), UInt8(truncatingIfNeeded: rc)])
    }

    private func flashRead(_ p: [UInt8]) {
        var addr = 0, n = 0
        if p.count >= 5 { addr = Int(p[0]) | Int(p[1]) << 8 | Int(p[2]) << 16 | Int(p[3]) << 24; n = Int(p[4]) }
        var out = Array(p.prefix(4)) + [UInt8(n), 0]
        if out.count < 6 { out = [0, 0, 0, 0, 0, 1] }
        if n == 0 || n > 128 || addr >= 0x100000 || n > 0x100000 - addr { out[5] = 1 }
        else { out += (0..<n).map { UInt8(truncatingIfNeeded: (addr + $0) &* 31) } }
        reply(0x65, out)
    }

    // MARK: The state record (pa_sysex.h, 128 bytes)

    func stateRecord() -> [UInt8] {
        func b(_ v: Int) -> UInt8 { UInt8(clamping: v) }
        let s = live
        var r = [UInt8](repeating: 0, count: DeviceStateLayout.size)
        r[0] = 1; r[1] = b(s.view); r[2] = b(s.preset); r[3] = b(s.flags); r[4] = b(s.presetVol); r[5] = b(s.outLevel)
        for (i, u) in s.name.unicodeScalars.prefix(16).enumerated() { r[6 + i] = UInt8(truncatingIfNeeded: u.value) }
        for i in 0..<8 {
            let o = 22 + i * 8, sl = s.slots[i]
            r[o] = sl.on ? 1 : 0; r[o + 1] = b(sl.type)
            for k in 0..<6 { r[o + 2 + k] = b(sl.knobs[k]) }
        }
        let g = s.g
        r[86] = b(g.inGain + 12); r[87] = b(g.gate + 80); r[88] = b(g.outType); r[89] = b(g.cabLine); r[90] = b(g.limiter); r[91] = b(g.fizz)
        r[92] = b(g.width); r[93] = b(g.routing); r[94] = b(g.balance + 50); r[95] = b(g.geq)
        for i in 0..<5 { r[96 + i] = b(g.bands[i] + 12) }
        r[101] = b(g.tunerRef - 430); r[102] = b(g.tunerMute); r[103] = b(btMode); r[104] = b(brightness); r[105] = b(homeView)
        r[106] = b(g.bpm & 0xFF); r[107] = b(g.bpm >> 8); r[108] = b(g.pattern); r[109] = b(g.gVol); r[110] = b(g.drums)
        for i in 0..<4 { r[111 + i] = b(s.stomp[i]) }
        r[115] = b(s.namCount); r[116] = s.userCab ? 1 : 0
        for i in 0..<8 { r[117 + i] = b(s.order[i]) }
        r[125] = b(s.cabCount); r[126] = b(s.namFree); r[127] = b(s.cabFree)
        return r
    }

    // MARK: Presets

    /// `pa_preset_save`: the record goes in with the slot's own seq + 1 and the EMPTY flag cleared.
    private func savePreset(_ i: Int, _ rec: PresetRecord) {
        var r = rec
        r.isEmpty = false
        r.seq = presets[i].seq &+ 1
        presets[i] = PresetRecord(record: r.encode())!
    }

    private func loadPreset(_ i: Int) {
        let r = presets[i]
        live.preset = i
        live.name = String(r.name.prefix(16)).trimmingCharacters(in: .whitespacesAndNewlines)
        live.presetVol = Int(r.presetVol)
        for s in 0..<8 {
            live.slots[s] = .init(on: r.slotEnableMask >> UInt8(s) & 1 != 0, type: Int(r.slotType[s]),
                                  knobs: r.params[s].map { PresetRecord.percent(q16: $0) })
        }
        live.order = r.slotOrder.map(Int.init)
        live.stomp = r.stompMap.map(Int.init)
        live.userCab = false
    }

    /// CC 88: the current sound into the current preset.
    private func saveCurrent() {
        let i = live.preset
        savePreset(i, PresetCopy.overlay(presets[i], live: live))
    }

    // MARK: Channel messages (usb_ble.c)

    private func handle(message m: [UInt8]) {
        guard let st = m.first, st >= 0x80 else { return }
        if st & 0xF0 == 0xC0, m.count >= 2, Int(m[1]) < PresetRecord.count { loadPreset(Int(m[1])) }
        if st & 0xF0 == 0xB0, m.count >= 3 { control(Int(m[1]), Int(m[2])) }
    }

    /// The direct-knob CCs 102...118: (slot, native knob).
    private static let directKnobs: [(Slot, Int)] = [
        (.amp, 0), (.amp, 5), (.amp, 1), (.amp, 2), (.amp, 3), (.amp, 4), (.drive, 0), (.dly, 0), (.dly, 1), (.dly, 2),
        (.rev, 0), (.rev, 3), (.mod, 0), (.mod, 1), (.cab, 0), (.cab, 1), (.cab, 2),
    ]

    private func control(_ c: Int, _ v: Int) {
        switch c {
        case 99: nrpnMod = v; haveMod = true; havePar = false; haveHi = false; return
        case 98: nrpnPar = v; havePar = true; haveHi = false; return
        case 101, 100: if v == 127 { haveMod = false; havePar = false; haveHi = false }; return
        case 6, 38:
            guard haveMod, havePar else { return }
            if c == 6 { nrpnHi = v; haveHi = true; nrpnApply(v, fine: false) }
            else if haveHi { nrpnApply(nrpnHi << 7 | v, fine: true) }
            return
        case 7: live.presetVol = (v * 100 + 63) / 127; return
        case 102...118:
            let (s, k) = Self.directKnobs[c - 102]
            live.slots[s.rawValue].knobs[k] = Int((Double(v * 16383 / 127) * 100 / 16383).rounded())
            return
        default: break
        }
        let hit = v >= 64
        if (28...35).contains(c) { setModule(c - 28, hit); return }
        switch c {
        case 85: live.setFlag(2, hit)
        case 86: live.setFlag(4, hit)
        case 87: live.setFlag(1, hit)
        case 20...27: if hit { toggleModule(c - 20) }
        case 80: if hit { loadPreset((live.preset + 1) % PresetRecord.count) }
        case 81: if hit { loadPreset((live.preset + PresetRecord.count - 1) % PresetRecord.count) }
        case 88: if hit { saveCurrent() }
        default: break
        }
    }

    private func setModule(_ module: Int, _ on: Bool) {
        if let s = Slot(module: module) { live.slots[s.rawValue].on = on }
    }

    private func toggleModule(_ module: Int) {
        if let s = Slot(module: module) { live.slots[s.rawValue].on.toggle() }
    }

    /// A complete data entry. `fine`: the low half (CC 38) arrived, so `d` is 14 bit; otherwise it is the CC 6 value alone.
    private func nrpnApply(_ d: Int, fine: Bool) {
        let par = nrpnPar
        switch nrpnMod {
        case 0...7:
            guard let s = Slot(module: nrpnMod) else { return }
            if par <= 5 || (0x60...0x65).contains(par) {
                let k = par <= 5 ? par : par - 0x60
                live.slots[s.rawValue].knobs[k] = fine ? Int((Double(d) * 100 / 16383).rounded()) : Int((Double(d) * 100 / 127).rounded())
            } else if par == 0x40 {
                let t = fine ? d >> 7 : d
                let type = t >= 0x20 ? t - 0x20 : t
                if type < typeCount(s) { live.slots[s.rawValue].type = type }
            } else if par == 0x41 {
                live.slots[s.rawValue].on = (fine ? d >> 7 : d) >= 64
            }
        case 8:
            if let p = GlobalParam(rawValue: par) { live.assign(p, raw: d) }
        case 9:
            if par == 0 { live.setFlag(4, d != 0) } else if let p = GrooveParam(rawValue: par) { live.assign(p, wire: d) }
        case 10:
            if par == 0 { live.presetVol = min(d, 100) }
            else if (3...6).contains(par), let s = Slot(module: d) { live.stomp[par - 3] = s.rawValue }
            else if par == 7, d >> 3 < 8 { live.order = MIDIControl.chainMove(live.order, slot: d >> 3, to: d & 7) }
        default: break
        }
    }

    private func typeCount(_ s: Slot) -> Int {
        switch s {
        case .amp: return typeNames(kind: 0).count
        case .cab: return typeNames(kind: 1).count
        default: return SimulatedFactory.fixedTypeCounts[s.rawValue]
        }
    }
}

enum DeviceStateLayout { static let size = 128 }
