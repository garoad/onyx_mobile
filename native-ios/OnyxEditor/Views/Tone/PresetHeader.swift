// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// The preset line of the Tone tab: name, P-number, step buttons, the P01...P80 menu, Read unit, Save and Save As.
struct PresetHeader: View {
    @Environment(AppModel.self) private var model
    let state: DeviceState

    private var session: OnyxSession { model.session }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                stepButton("chevron.left", label: "Previous preset") { session.uiPreviousPreset() }
                presetMenu
                stepButton("chevron.right", label: "Next preset") { session.uiNextPreset() }
            }
            ViewThatFits(in: .horizontal) {
                actions(compactLabels: false)
                actions(compactLabels: true)
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
    }

    private func stepButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            Image(systemName: icon).font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    private var presetMenu: some View {
        Menu {
            Picker("Preset", selection: Binding(get: { state.preset }, set: { session.uiSelectPreset($0) })) {
                ForEach(0..<PresetRecord.count, id: \.self) { i in
                    Text(menuTitle(i)).tag(i)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(state.name.isEmpty ? "-" : state.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 8) {
                    Text(presetLabel(state.preset)).font(.subheadline.monospaced()).foregroundStyle(Palette.mid)
                    if state.isStompMode {
                        Text("STOMP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.onColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.mid)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(Text("Preset"))
        .accessibilityValue(Text("\(presetLabel(state.preset)) \(state.name)\(state.isStompMode ? ", STOMP" : "")"))
        .accessibilityHint(Text("Opens the list of presets"))
    }

    private func menuTitle(_ i: Int) -> String {
        if let info = session.uiPresetInfo(i), !info.name.isEmpty { return "\(presetLabel(i))  \(info.name)" }
        return presetLabel(i)
    }

    private func actions(compactLabels: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await session.uiRefresh()
                    if let s = session.state { model.showToast(String(localized: "On the unit now: \(presetLabel(s.preset))  \(s.name)")) }
                }
            } label: {
                Label(compactLabels ? "Read" : "Read unit", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(session.busy)

            Button {
                session.uiSaveCurrent()
                Haptics.success()
                model.showToast(String(localized: "Saved to \(presetLabel(state.preset))"))
            } label: {
                Label("SAVE", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.busy)
            .accessibilityHint(Text("Stores the sound on the unit in this preset (CC 88)"))

            Button {
                model.presentSaveAs(source: state.preset)
            } label: {
                Label(compactLabels ? "Save As" : "Save As…", systemImage: "plus.square.on.square").frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(session.busy)
            .accessibilityHint(Text("Copies this sound to another preset number"))
        }
        .lineLimit(1)
    }
}
