// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import Foundation
import OnyxKit

/// Launch arguments that make screenshots scriptable: `-simulatedUnit` (connects at once), `-startTab N` (0 Tone ... 4 Library),
/// `-showSaveAs`, `-showMIDIHelp`, `-showSettings`, `-showConnect`.
enum DebugLaunch {
    @MainActor static func apply(_ model: AppModel, arguments a: [String]) async {
        if let i = a.firstIndex(of: "-startTab"), a.indices.contains(i + 1), let n = Int(a[i + 1]), AppSection.allCases.indices.contains(n) {
            model.section = AppSection.allCases[n]
        }
        if a.contains("-simulatedUnit") {
            await model.session.uiConnect(SimulatedUnit(name: "Pocket AMP (Simulator)", isBLE: false))
            model.session.startLiveSync()
        }
        if a.contains("-showConnect") { model.showConnect = true }
        if a.contains("-showSaveAs") {
            try? await Task.sleep(for: .milliseconds(500))
            model.presentSaveAs(source: model.session.state?.preset ?? 0)
        }
        if a.contains("-showSettings") { model.showSettings = true }
        if a.contains("-showMIDIHelp") {
            model.settingsPath = [.midiHelp]
            model.showSettings = true
        }
    }
}
#endif
