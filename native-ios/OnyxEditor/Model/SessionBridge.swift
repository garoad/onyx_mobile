// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OnyxKit

/// The only place the views touch `OnyxSession`'s API, so a change of its signatures is fixed in this one file.
/// Setters that are `async` in the session are fire-and-forget here (the session orders them itself).
extension OnyxSession {
    struct PresetInfo { var name: String; var isEmpty: Bool }

    var uiStatusText: String { status }
    var uiDeviceName: String { transportName }
    var uiLog: [String] { log }
    var uiIsLoadingSummaries: Bool { isLoadingSummaries }
    var uiLiveSync: Bool {
        get { isLiveSyncing }
        set { if newValue { startLiveSync() } else { stopLiveSync() } }
    }

    func uiPresetInfo(_ i: Int) -> PresetInfo? {
        guard presetSummaries.indices.contains(i), let s = presetSummaries[i] else { return nil }
        return PresetInfo(name: s.name, isEmpty: s.isEmpty)
    }

    func uiConnect(_ t: any OnyxTransport) async { _ = await connect(t) }
    func uiBeginEditing(_ c: EditedControl) { beginEditing(c) }
    func uiEndEditing(_ c: EditedControl) { endEditing(c) }
    func uiSetSlot(_ s: Slot, on: Bool) { Task { await setSlotEnabled(s, on) } }
    func uiSetModel(_ s: Slot, _ index: Int) { Task { await setModel(s, index) } }
    func uiSetKnob(_ s: Slot, _ k: Int, _ v: Int) { setKnob(s, k, v) }
    func uiSetPresetVolume(_ v: Int) { setPresetVolume(v) }
    func uiSetGlobal(_ p: GlobalParam, _ raw: Int) { setGlobal(p, raw) }
    func uiSetGroove(_ p: GrooveParam, _ v: Int) { setGroove(p, v) }
    func uiSetGroovePlaying(_ on: Bool) { Task { await setGroovePlaying(on) } }
    func uiSetStompKey(_ i: Int, module: Int) { Task { await setStompKey(i, module: module) } }
    func uiToggleTuner() { Task { await setTuner(!(state?.tunerOpen ?? false)) } }
    func uiNextPreset() { Task { await nextPreset() } }
    func uiPreviousPreset() { Task { await previousPreset() } }
    func uiSelectPreset(_ i: Int) { Task { await selectPreset(i) } }
    func uiSaveCurrent() { Task { await saveCurrent() } }
    func uiMoveSlot(_ s: Slot, to: Int) async { await moveSlot(s, to: to) }
    func uiRefresh() async { await refresh() }
    func uiLoadPresetSummaries() async { await loadPresetSummaries() }
    func uiCopyPreset(from: Int, to: Int, name: String) async throws { _ = try await copyPreset(from: from, to: to, name: name) }
}
