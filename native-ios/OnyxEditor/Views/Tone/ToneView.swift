// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct ToneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let state = model.session.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PresetHeader(state: state)
                    ChainView(state: state)
                    LevelsPanel(state: state)
                    Text("Hold a block's title bar for one second, then drag it onto another block to change the signal order.")
                        .font(.footnote).foregroundStyle(Palette.mid)
                }
                .padding(16)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            NotConnectedView()
        }
    }
}

private struct LevelsPanel: View {
    @Environment(AppModel.self) private var model
    let state: DeviceState

    var body: some View {
        Panel {
            SectionTitle("Level")
            ValueSlider(title: String(localized: "Preset volume"), value: state.presetVol, range: 0...100,
                        onEditing: { $0 ? model.session.uiBeginEditing(.presetVolume) : model.session.uiEndEditing(.presetVolume) },
                        onChange: { model.session.uiSetPresetVolume($0) })
            ValueSlider(title: String(localized: "Output level"), value: state.outLevel, range: 0...100,
                        onEditing: { $0 ? model.session.uiBeginEditing(.global(.outputLevel)) : model.session.uiEndEditing(.global(.outputLevel)) },
                        onChange: { model.session.uiSetGlobal(.outputLevel, $0) })
        }
    }
}

#if DEBUG
#Preview("Tone") {
    PreviewHost { ToneView() }
}
#endif
