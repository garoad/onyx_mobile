// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import OnyxKit

/// The editor's `TABLES` (generated from the web editor by tools/gen_editor_tables.py) and `knobLabels()`.
enum ChainTables {
    /// Model names per block; AMP and CAB come from the unit (`OnyxSession.ampNames` / `cabNames`).
    static let models: [String: [String]] = [
        "DYN": ["GATE","BOOST+GATE","COMP+GATE","AI GATE MS","COMP"],
        "DRIVE": ["TS-808","KLON","OCD","RAT","BIG MUFF","FUZZ FACE"],
        "EQ": ["5-BAND","LOW/HIGH CUT","PARAMETRIC-3"],
        "MOD": ["CHORUS","PHASER","FLANGER","TREMOLO","VIBRATO","WAH","AUTO WAH"],
        "DLY": ["ANALOG","DUCKING","TAPE","DUAL","LO-FI","DIGITAL","PING PONG","REVERSE","SLAPBACK"],
        "REV": ["ROOM","HALL","SWELL","SPRING","SHIMMER","CLOUD","PLATE"],
    ]

    static let dyn: [[String]] = [
        ["THRESH","RELEASE","ATTACK","LEVEL"],
        ["THRESH","RELEASE","---","BOOST"],
        ["THRESH","RATIO","ATTACK","LEVEL"],
        ["THRESH","RELEASE","ATTACK","LEVEL"],
        ["THRESH","RATIO","ATTACK","LEVEL"],
    ]
    static let drive: [String] = ["DRIVE","TONE","LEVEL"]
    static let amp: [String] = ["GAIN","BASS","MID","TREBLE","PRES","MASTER"]
    static let cab: [String] = ["LEVEL","LOWCUT","HICUT"]
    static let eq: [[String]] = [
        ["100","400","1k","3k","8k"],
        ["LOWCUT","HICUT","LEVEL"],
        ["LOW","MID","FREQ","HIGH"],
    ]
    static let mod: [[String]] = [
        ["RATE","DEPTH","MIX","---"],
        ["RATE","DEPTH","MIX","FDBK"],
        ["RATE","DEPTH","MIX","FDBK"],
        ["RATE","DEPTH","---","---"],
        ["RATE","DEPTH","---","---"],
        ["RATE","RANGE","MIX","RESO"],
        ["FALL","SENS","MIX","RESO"],
    ]
    /// DLY: the three shared labels, then the fourth knob's label per type.
    static let dlyBase: [String] = ["TIME","FDBK","MIX"]
    static let dlyFourth: [String] = ["MOD","RELEASE","GRIT","RATIO","GRIT","TONE","TONE","TONE","TONE"]
    static let rev: [String] = ["DECAY","LOWCUT","TONE","MIX"]

    /// Knob count per block (`TABLES.counts`); EQ depends on its type (see `eqCounts`).
    static let counts: [String: Int] = ["DYN": 4, "DRIVE": 3, "AMP": 6, "CAB": 3, "MOD": 4, "DLY": 4, "REV": 4]
    static let eqCounts: [Int] = [5,3,4]

    struct KnobLabels {
        /// One label per knob; "---" or "" marks a knob the model does not use.
        var labels: [String]
        var count: Int

        func isDead(_ i: Int) -> Bool { i >= count || i >= labels.count || labels[i].isEmpty || labels[i] == "---" }
    }

    /// `knobLabels(nm, type)` of the web editor.
    static func knobLabels(_ slot: Slot, type: Int) -> KnobLabels {
        let t = max(type, 0)
        switch slot {
        case .dyn: return .init(labels: dyn[t % dyn.count], count: counts["DYN"] ?? 4)
        case .mod: return .init(labels: mod[t % mod.count], count: counts["MOD"] ?? 4)
        case .eq: return .init(labels: eq[t % 3], count: eqCounts[t % 3])
        case .dly: return .init(labels: dlyBase + [dlyFourth[t % dlyFourth.count]], count: counts["DLY"] ?? 4)
        case .rev: return .init(labels: t == 7 ? ["SIZE"] + rev.dropFirst() : rev, count: counts["REV"] ?? 4)
        case .drive: return .init(labels: drive, count: counts["DRIVE"] ?? 3)
        case .amp: return .init(labels: amp, count: counts["AMP"] ?? 6)
        case .cab: return .init(labels: cab, count: counts["CAB"] ?? 3)
        }
    }
}
