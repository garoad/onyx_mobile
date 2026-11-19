// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// A control of the editor that can be held by a finger: while it is, a state refresh must not move it (the web editor's `dragging`).
public enum EditedControl: Hashable, Sendable {
    case knob(Slot, Int)
    case presetVolume
    case global(GlobalParam)
    case groove(GrooveParam)
}

extension ControlSpec.Kind {
    func clamp(_ v: Int) -> Int {
        switch self {
        case .slider(let r): return min(max(v, r.lowerBound), r.upperBound)
        case .picker(let o): return min(max(v, 0), o.count - 1)
        case .toggle: return min(max(v, 0), 1)
        }
    }
}

/// Writes into a decoded state what the unit does when it receives the same NRPN: the optimistic update of the session and the live state of the simulated unit.
extension DeviceState {
    /// The flag bits that live in `g` (USB loopback b3, USB mode b5...6); b0 STOMP, b1 tuner, b2 groove and b4 (stereo cab, reserved 1) are kept.
    mutating func syncFlags() {
        flags = (flags & 0x17) | ((g.loopback & 1) << 3) | ((g.usbMode & 3) << 5)
    }

    mutating func setFlag(_ bit: Int, _ on: Bool) { flags = on ? flags | bit : flags & ~bit }

    /// NRPN module 8; `raw` is the raw number, clamped to the control's range.
    mutating func assign(_ p: GlobalParam, raw: Int) {
        let v = p.spec.kind.clamp(raw)
        switch p {
        case .inputGain: g.inGain = v - 12
        case .inputGate: g.gate = v - 80
        case .outputLevel: outLevel = v
        case .outputType: g.outType = v
        case .cabOnLine: g.cabLine = v
        case .limiter: g.limiter = v
        case .fizz: g.fizz = v
        case .width: g.width = v
        case .routing: g.routing = v
        case .balance: g.balance = v - 50
        case .globalEQ: g.geq = v
        case .eq100: g.bands[0] = v - 12
        case .eq400: g.bands[1] = v - 12
        case .eq1k: g.bands[2] = v - 12
        case .eq3k: g.bands[3] = v - 12
        case .eq8k: g.bands[4] = v - 12
        case .tunerReference: g.tunerRef = v + 430
        case .tunerMute: g.tunerMute = v
        case .usbLoopback: g.loopback = v
        case .usbMode: g.usbMode = v
        }
        syncFlags()
    }

    /// NRPN module 9; `wire` is the number on the wire (the BPM travels as `bpm - 40`).
    mutating func assign(_ p: GrooveParam, wire: Int) {
        switch p {
        case .bpm: g.bpm = min(max(wire, 0), 220) + 40
        case .pattern: g.pattern = min(max(wire, 0), 39)
        case .volume: g.gVol = min(max(wire, 0), 100)
        case .drums: g.drums = min(max(wire, 0), 1)
        }
    }

    /// Takes the value of one control from another state.
    mutating func adopt(_ c: EditedControl, from old: DeviceState) {
        switch c {
        case .knob(let s, let k): slots[s.rawValue].knobs[k] = old.slots[s.rawValue].knobs[k]
        case .presetVolume: presetVol = old.presetVol
        case .global(let p): assign(p, raw: p.value(in: old))
        case .groove(let p): assign(p, wire: p.wire(p.value(in: old)))
        }
    }
}

extension Slot {
    /// The slot an NRPN module number / CC 28+n number addresses (`SLOT_MODULE` inverted).
    init?(module: Int) {
        guard let s = Slot.allCases.first(where: { $0.module == module }) else { return nil }
        self = s
    }
}
