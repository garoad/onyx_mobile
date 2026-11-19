// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// What a fresh Pocket AMP holds: the stock model names (reference/firmware/stock_assets.c), 40 factory-like presets and 40 EMPTY user slots.
enum SimulatedFactory {
    static let stockAmps = [
        "1 UK Clean", "2 US Clean", "3 JP Chorus Clean", "4 Blues Overdrive", "5 Hard Overdrive", "6 Tube Overdrive", "7 Boutique Drive",
        "8 Dark Distortion", "9 UK Stack Gain", "10 US Crunch Gain", "11 US High Gain", "12 Hot-Rod British", "13 Smooth Lead", "14 UK Combo 40",
        "15 UK Modern Stack", "16 US Tube Bass", "17 Arena Bass", "18 Studio Bass", "19 Modern Bass OD", "20 Euro Clean Bass",
    ]
    static let stockCabs = [
        "1 Vintage 4x12", "2 UK Slant 4x12", "3 British 4x12", "4 Hot-Rod 4x12", "5 Full-Range Flat", "6 Boutique 2x12", "7 UK Chime 2x12",
        "8 Hot-Rod 1x12", "9 US Combo 1x12", "10 US Custom 4x12", "11 US Twin 2x12", "12 US Oversize 4x12", "13 UK Hi-Power 4x12",
        "14 US Modern 1x12", "15 JP Clean 2x12", "16 Studio Bass 4x10", "17 Arena Bass 4x10", "18 Neo Bass 2x12", "19 Euro Bass 2x10", "20 UK Bass 4x12",
    ]
    static let presetNames = [
        "Clean Sparkle", "Glassy Clean", "Jazz Box", "Chime Clean", "Studio Clean", "Country Twang", "Blues Breaker", "Edge of Crunch",
        "British Crunch", "Classic Rock", "Plexi Drive", "Hot Rod", "Tweed Crunch", "Pub Rock", "Punk Rhythm", "Indie Jangle", "Modern Lead",
        "Singing Lead", "Smooth Sustain", "Fusion Lead", "Arena Lead", "Shred", "Heavy Rhythm", "Tight Metal", "Thrash", "Djent", "Doom",
        "Stoner Fuzz", "Funk Bass", "Slap Bass", "Rock Bass", "Finger Bass", "Bass Drive", "Acoustic Sim", "Ambient Pad", "Shimmer Wash",
        "Space Echo", "Tape Slap", "Spring Surf", "Worship Swell",
    ]

    /// Model counts per slot id for the fixed tables (`TABLES.models`); AMP and CAB follow the name lists.
    static let fixedTypeCounts = [5, 6, 0, 0, 3, 7, 9, 7]

    static let factoryCount = 40
    static let defaultOrder: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7]
    static let defaultStomp: [UInt8] = [1, 5, 6, 7]

    /// `preset_set_neutral`: every knob 50 % except the ones the firmware sets differently.
    static func neutralParams() -> [[UInt16]] {
        var p = [[UInt16]](repeating: [UInt16](repeating: PresetRecord.q16(percent: 50), count: 6), count: 8)
        p[Slot.cab.rawValue][0] = PresetRecord.q16(percent: 100)
        p[Slot.cab.rawValue][1] = 0
        p[Slot.cab.rawValue][2] = 0
        p[Slot.rev.rawValue][1] = 0
        p[Slot.dyn.rawValue][3] = PresetRecord.q16(percent: 100)
        p[Slot.dly.rawValue][1] = PresetRecord.q16(percent: 15)
        p[Slot.dly.rawValue][2] = PresetRecord.q16(percent: 10)
        p[Slot.mod.rawValue][2] = PresetRecord.q16(percent: 12)
        return p
    }

    /// `init_single_preset`: P01...P40 are factory-like sounds, P41...P80 are EMPTY. The record is untouched (seq 1).
    static func record(_ i: Int) -> PresetRecord {
        var p = neutralParams()
        var r = PresetRecord(seq: 1, name: "EMPTY", bpm: 120, genre: 7, customCabIdx: 255, customCabBlend: 100, inputTrimDb: 0, gateThresholdPct: 0,
                             slotEnableMask: 0, slotOrder: defaultOrder, ampModel: 0, cabModel: 0, presetVol: 70, flags: PresetRecord.flagEmpty,
                             slotType: [UInt8](repeating: 0, count: 8), stompMap: defaultStomp, params: p)
        if i >= factoryCount {
            r.slotType[Slot.dyn.rawValue] = 3
            return r
        }
        let bass = (28...32).contains(i)
        let amp = bass ? 15 + (i - 28) % 5 : i % 15
        let cab = bass ? 15 + (i - 28) % 5 : (i * 4) % 15
        let types = [i % 5, i % 6, amp, cab, i % 3, i % 7, i % 5, i % 6]
        r.name = presetNames[i]
        r.isEmpty = false
        r.bpm = 120
        r.genre = UInt8(i / 5 % 7)
        r.presetVol = UInt8(60 + i % 4 * 5)
        r.ampModel = UInt8(amp); r.cabModel = UInt8(cab)
        r.slotType = types.map { UInt8($0) }
        var mask: UInt8 = 1 << UInt8(Slot.amp.rawValue) | 1 << UInt8(Slot.cab.rawValue)
        if i % 5 == 0 { mask |= 1 << UInt8(Slot.drive.rawValue) }
        if i % 2 == 0 { mask |= 1 << UInt8(Slot.dly.rawValue) }
        if i % 3 == 0 { mask |= 1 << UInt8(Slot.rev.rawValue) }
        if i % 4 == 1 { mask |= 1 << UInt8(Slot.mod.rawValue) }
        r.slotEnableMask = mask
        let q = PresetRecord.q16(percent:)
        p[Slot.amp.rawValue] = [q(20 + i * 13 % 70), q(30 + i * 7 % 50), q(40 + i * 11 % 40), q(50), q(40 + i * 5 % 40), q(50 + i * 3 % 40)]
        p[Slot.drive.rawValue][0] = q(30 + i * 9 % 60)
        p[Slot.rev.rawValue][3] = q(15 + i * 4 % 30)
        r.params = p
        return r
    }
}
