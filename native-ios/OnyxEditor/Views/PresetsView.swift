// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct PresetsView: View {
    @Environment(AppModel.self) private var model

    private var session: OnyxSession { model.session }

    var body: some View {
        if session.isConnected {
            List {
                if session.uiIsLoadingSummaries {
                    ProgressView(value: session.summaryProgress) { Text("Reading preset names…").font(.footnote) }
                        .listRowBackground(Palette.surface)
                }
                ForEach(0..<PresetRecord.count, id: \.self) { i in row(i) }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 44)
            .refreshable { await session.uiLoadPresetSummaries() }
            .task { await session.uiLoadPresetSummaries() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await session.uiLoadPresetSummaries() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(session.busy)
                }
            }
        } else {
            NotConnectedView()
        }
    }

    private func row(_ i: Int) -> some View {
        let info = session.uiPresetInfo(i)
        let current = session.state?.preset == i
        let name = info.map { $0.isEmpty ? String(localized: "EMPTY") : $0.name } ?? (current ? (session.state?.name ?? "…") : "…")
        return Button {
            Haptics.tick()
            session.uiSelectPreset(i)
        } label: {
            HStack(spacing: 12) {
                Text(presetLabel(i)).font(.body.monospaced().weight(.semibold)).foregroundStyle(current ? Palette.accent : Palette.mid).frame(width: 52, alignment: .leading)
                Text(name).foregroundStyle(info?.isEmpty == true ? Palette.mid : Palette.text).lineLimit(1)
                Spacer()
                if current { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Palette.accent).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(current ? Palette.accent.opacity(0.14) : Color.clear)
        .swipeActions(edge: .trailing) {
            Button { model.presentSaveAs(source: i) } label: { Label("Save As…", systemImage: "plus.square.on.square") }
                .tint(Palette.accent)
        }
        .contextMenu {
            Button { session.uiSelectPreset(i) } label: { Label("Select", systemImage: "checkmark.circle") }
            Button { model.presentSaveAs(source: i) } label: { Label("Save As…", systemImage: "plus.square.on.square") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(presetLabel(i)), \(name)"))
        .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: Text("Save As…")) { model.presentSaveAs(source: i) }
    }
}

#if DEBUG
#Preview("Presets") { PreviewHost { PresetsView() } }
#endif
