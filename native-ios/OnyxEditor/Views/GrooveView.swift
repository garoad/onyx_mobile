// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct GrooveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let state = model.session.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    groovePanel(state)
                    stompPanel(state)
                    tunerPanel(state)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else {
            NotConnectedView()
        }
    }

    private func groovePanel(_ state: DeviceState) -> some View {
        Panel {
            SectionTitle("Groove station")
            ToggleRow(title: String(localized: "Groove playing"), isOn: state.groovePlaying) { model.session.uiSetGroovePlaying($0) }
            ForEach(GrooveParam.allCases, id: \.self) { p in
                Divider().overlay(Palette.line)
                SpecControlRow(
                    spec: p.spec, value: p.value(in: state),
                    onEditing: { $0 ? model.session.uiBeginEditing(.groove(p)) : model.session.uiEndEditing(.groove(p)) },
                    onChange: { model.session.uiSetGroove(p, $0) })
            }
        }
    }

    private func stompPanel(_ state: DeviceState) -> some View {
        Panel {
            SectionTitle("Stomp keys")
            Text("In STOMP mode each foot key switches one block.").font(.footnote).foregroundStyle(Palette.mid)
            ForEach(0..<4, id: \.self) { i in
                // The state holds a slot id, the NRPN wants a module number.
                let module = Slot(rawValue: state.stomp[i])?.module ?? 0
                PickerRow(title: String(localized: "Key \(Stomp.keys[i])"), options: Stomp.moduleNames, selection: module) { model.session.uiSetStompKey(i, module: $0) }
            }
        }
    }

    private func tunerPanel(_ state: DeviceState) -> some View {
        Panel {
            SectionTitle("Tuner")
            HStack {
                Button {
                    model.session.uiToggleTuner()
                } label: {
                    Label(state.tunerOpen ? "Close tuner" : "Open tuner", systemImage: "tuningfork").frame(minHeight: 36)
                }
                .buttonStyle(.bordered)
                if state.tunerOpen {
                    Text("The tuner is open on the unit").font(.footnote).foregroundStyle(Palette.accent)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Groove") { PreviewHost { GrooveView() } }
#endif
