// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// How a control on the Unit tab looks and what raw number it sends. The value a control holds is always the RAW number
/// of NRPN module 8 / 9 (reference/MIDI-MAP-CUSTOM.md section 6); `format` turns it into the text next to the slider.
public struct ControlSpec: Sendable {
    public enum Kind: Sendable {
        case slider(ClosedRange<Int>)
        case picker([String])
        case toggle
    }

    public var kind: Kind
    public var title: String
    public var format: (@Sendable (Int) -> String)?

    public func text(_ v: Int) -> String { format?(v) ?? String(v) }
}

/// NRPN module 8, the unit's global settings. `rawValue` is the NRPN parameter number.
public enum GlobalParam: Int, CaseIterable, Sendable {
    case inputGain = 0, inputGate = 1, outputLevel = 2, outputType = 3, cabOnLine = 4, limiter = 5, fizz = 6, width = 7
    case routing = 8, balance = 9, globalEQ = 10, eq100 = 11, eq400 = 12, eq1k = 13, eq3k = 14, eq8k = 15
    case tunerReference = 16, tunerMute = 17, usbLoopback = 18, usbMode = 19

    /// The controls of the Global tab, in the web editor's order (`GLOBALS`). `outputLevel` lives with the levels on the Tone tab.
    public static let globalTabOrder: [GlobalParam] = [
        .inputGain, .inputGate, .outputType, .cabOnLine, .limiter, .fizz, .width, .routing, .balance, .globalEQ,
        .eq100, .eq400, .eq1k, .eq3k, .eq8k, .tunerReference, .tunerMute, .usbMode, .usbLoopback,
    ]

    public var spec: ControlSpec {
        let db: @Sendable (Int) -> String = { "\($0 - 12) dB" }
        switch self {
        case .inputGain: return .init(kind: .slider(0...24), title: "Input gain", format: db)
        case .inputGate: return .init(kind: .slider(0...50), title: "Input gate", format: { $0 == 0 ? "off" : "\($0 - 80) dB" })
        case .outputLevel: return .init(kind: .slider(0...100), title: "Output level", format: nil)
        case .outputType: return .init(kind: .picker(["phones", "line"]), title: "Output", format: nil)
        case .cabOnLine: return .init(kind: .toggle, title: "Cab on line out", format: nil)
        case .limiter: return .init(kind: .picker(["brickwall", "soft", "off"]), title: "Limiter", format: nil)
        case .fizz: return .init(kind: .slider(0...3), title: "Fizz filter", format: nil)
        case .width: return .init(kind: .slider(0...100), title: "Stereo width", format: nil)
        case .routing: return .init(kind: .picker(["stereo", "mono", "left", "right", "swap"]), title: "Routing", format: nil)
        case .balance: return .init(kind: .slider(0...100), title: "Balance", format: { "\($0 - 50)" })
        case .globalEQ: return .init(kind: .toggle, title: "Global EQ", format: nil)
        case .eq100: return .init(kind: .slider(0...24), title: "EQ 100", format: db)
        case .eq400: return .init(kind: .slider(0...24), title: "EQ 400", format: db)
        case .eq1k: return .init(kind: .slider(0...24), title: "EQ 1k", format: db)
        case .eq3k: return .init(kind: .slider(0...24), title: "EQ 3k", format: db)
        case .eq8k: return .init(kind: .slider(0...24), title: "EQ 8k", format: db)
        case .tunerReference: return .init(kind: .slider(0...20), title: "Tuner reference", format: { "\(430 + $0) Hz" })
        case .tunerMute: return .init(kind: .toggle, title: "Tuner muted", format: nil)
        case .usbLoopback: return .init(kind: .toggle, title: "USB loopback", format: nil)
        case .usbMode:
            return .init(kind: .picker(["AMP (the unit's sound + the PC's)", "INTERFACE (the PC's audio only; the PC records the dry guitar)",
                                        "INTERFACE + direct monitor (the dry guitar is also heard)"]), title: "USB audio mode", format: nil)
        }
    }

    /// The raw value of this setting in a decoded state record (`GLOBALS[].get`).
    public func value(in s: DeviceState) -> Int {
        let g = s.g
        switch self {
        case .inputGain: return g.inGain + 12
        case .inputGate: return g.gate + 80
        case .outputLevel: return s.outLevel
        case .outputType: return g.outType
        case .cabOnLine: return g.cabLine
        case .limiter: return g.limiter
        case .fizz: return g.fizz
        case .width: return g.width
        case .routing: return g.routing
        case .balance: return g.balance + 50
        case .globalEQ: return g.geq
        case .eq100: return g.bands[0] + 12
        case .eq400: return g.bands[1] + 12
        case .eq1k: return g.bands[2] + 12
        case .eq3k: return g.bands[3] + 12
        case .eq8k: return g.bands[4] + 12
        case .tunerReference: return g.tunerRef - 430
        case .tunerMute: return g.tunerMute
        case .usbLoopback: return g.loopback
        case .usbMode: return g.usbMode
        }
    }

    public var nrpn: (module: Int, param: Int) { (8, rawValue) }
}

/// NRPN module 9, the Groove Station. The play/stop switch is CC 86, not an NRPN.
public enum GrooveParam: Int, CaseIterable, Sendable {
    case bpm = 1, pattern = 2, volume = 3, drums = 4

    public var spec: ControlSpec {
        switch self {
        case .bpm: return .init(kind: .slider(40...260), title: "BPM", format: nil)
        case .pattern: return .init(kind: .slider(0...39), title: "Pattern", format: { "\($0 + 1)" })
        case .volume: return .init(kind: .slider(0...100), title: "Groove volume", format: nil)
        case .drums: return .init(kind: .toggle, title: "Drums on", format: nil)
        }
    }

    public func value(in s: DeviceState) -> Int {
        switch self {
        case .bpm: return s.g.bpm
        case .pattern: return s.g.pattern
        case .volume: return s.g.gVol
        case .drums: return s.g.drums
        }
    }

    /// The raw number sent: the BPM is sent as `bpm - 40`.
    public func wire(_ v: Int) -> Int { self == .bpm ? v - 40 : v }
}

/// The four STOMP-mode foot keys (NRPN module 10, parameters 3...6). Each one picks a MODULE number (not a slot id).
public enum Stomp {
    public static let keys = ["VOL-", "VOL+", "<", ">"]
    /// Module number -> name (`MODNAMES`).
    public static let moduleNames = ["DYN", "AMP", "MOD", "DLY", "REV", "CAB", "DRIVE", "EQ"]
}
