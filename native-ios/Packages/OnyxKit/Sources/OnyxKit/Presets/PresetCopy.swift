// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// "Save as": copy the sound that is on the unit now into another preset number. The web editor has no such feature (its "save" is CC 88: the current
/// sound into the current preset).
///
/// The unit can only be asked for a STORED preset (cmd 83, the 164-byte record) and for the LIVE state (cmd 80, 128 bytes: per slot on / type / six knob
/// percentages, the chain order, the preset volume, the stomp map). A copy therefore starts from the stored record of the source preset (it carries
/// what the live state does not: BPM, genre, custom cab, input trim, gate threshold, the full-resolution Q16 knobs, the 23-character name) and lays the
/// live state over it, so an edit that was not saved yet travels with the copy: what CC 88 would have stored in the source slot.
///
/// The destination is written with the preset upload cmd 25 target 0 (`PA_UPLOAD_PRESET` = the firmware's `pa_preset_save`, the editor's save), NOT
/// target 4 (the backup restore, which keeps seq and the EMPTY flag as given): `pa_preset_save` clears EMPTY and bumps the slot's own seq, which is
/// what turns an empty or untouched factory slot into a saved one. The record only has to carry its magic and CRC.
public enum PresetCopy {
    /// The upload target of the copy (`PA_UPLOAD_PRESET`).
    public static let uploadTarget: UInt8 = 0

    /// The stored record of a preset with the live state laid over it (the name is the stored one).
    ///
    /// A knob keeps its stored full-resolution Q16 value when the live percentage is the same percentage, so an untouched knob is not rounded.
    /// A live user cabinet (RAM only, not a stored one) cannot be copied: the stored cabinet stays.
    public static func overlay(_ stored: PresetRecord, live: DeviceState) -> PresetRecord {
        var r = stored
        r.presetVol = UInt8(clamping: live.presetVol)
        var mask: UInt8 = 0
        for s in Slot.allCases {
            let st = live.slots[s.rawValue]
            if st.on { mask |= 1 << UInt8(s.rawValue) }
            if !(s == .cab && live.userCab) { r.slotType[s.rawValue] = UInt8(clamping: st.type) }
            for k in 0..<6 where PresetRecord.percent(q16: r.params[s.rawValue][k]) != st.knobs[k] {
                r.params[s.rawValue][k] = PresetRecord.q16(percent: st.knobs[k])
            }
        }
        r.slotEnableMask = mask
        r.slotOrder = live.order.map { UInt8(clamping: $0) }
        r.stompMap = live.stomp.map { UInt8(clamping: $0) }
        r.ampModel = r.slotType[Slot.amp.rawValue]
        r.cabModel = r.slotType[Slot.cab.rawValue]
        return r
    }

    /// The record to upload into the destination slot.
    /// - Parameters:
    ///   - stored: the stored record of the source preset (cmd 83).
    ///   - live: the live state while that preset is the one on the unit, or nil to copy the stored record only.
    ///   - name: the name of the copy, cut to 23 characters.
    public static func record(base stored: PresetRecord, live: DeviceState?, name: String) -> PresetRecord {
        var r = live.map { overlay(stored, live: $0) } ?? stored
        r.name = String(name.prefix(PresetRecord.maxNameLength))
        r.isEmpty = false
        return r
    }

    /// True when the live sound differs from the stored preset (it was edited and not saved yet).
    public static func hasUnsavedChanges(stored: PresetRecord, live: DeviceState) -> Bool {
        overlay(stored, live: live) != stored
    }

    /// The default name offered for a copy of `name` ("Clean" -> "Clean 2"), at most 23 characters.
    public static func suggestedName(for name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { return "NEW" }
        var stem = base, n = 2
        if let r = base.range(of: #" (\d{1,2})$"#, options: .regularExpression), let v = Int(base[r].trimmingCharacters(in: .whitespaces)) {
            stem = String(base[..<r.lowerBound]); n = v + 1
        }
        let suffix = " \(n)"
        return String(stem.prefix(PresetRecord.maxNameLength - suffix.count)) + suffix
    }

    /// Two records are the same sound when everything but the commit counter (seq) is equal: the read-back check after a copy.
    public static func sameSound(_ a: PresetRecord, _ b: PresetRecord) -> Bool {
        var x = a, y = b
        x.seq = 0; y.seq = 0
        return x == y
    }
}
