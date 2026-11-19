// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// One command in full: big monospaced hex and decimal bytes with Copy buttons, the value rule and the notes.
struct MIDICommandDetail: View {
    @Environment(AppModel.self) private var model
    let command: MIDICommand
    var embedded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(command.group.title)).font(.footnote).foregroundStyle(Palette.mid)
                    Text(L(command.title)).font(.title2.weight(.semibold))
                    HStack {
                        Text(command.label).font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(Palette.accent)
                        if command.status != .implemented { StatusBadge(status: command.status) }
                    }
                    Text(command.summary).foregroundStyle(Palette.mid)
                }
                bytesCard(title: "Hex", text: command.hexString, copy: command.hexString)
                bytesCard(title: "Decimal", text: command.decimalString, copy: command.decimalString)
                Panel {
                    SectionTitle("Value")
                    Text(L(command.valueRule))
                }
                if !command.notes.isEmpty {
                    Panel {
                        SectionTitle("Notes")
                        Text(L(command.notes))
                    }
                }
                Button {
                    copy(MIDICommandCatalog.plainText(for: command), message: String(localized: "Copied the command"))
                } label: {
                    Label("Copy as text", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(embedded ? Color.clear : Palette.bg)
        .navigationTitle(embedded ? Text("") : Text(L(command.title)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bytesCard(title: LocalizedStringKey, text: String, copy value: String) -> some View {
        Panel {
            HStack {
                SectionTitle(title)
                Spacer()
                Button {
                    copy(value, message: String(localized: "Copied the bytes"))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(minHeight: 44)
                }
                .accessibilityLabel(Text("Copy the bytes"))
            }
            Text(text)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ s: String, message: String) {
        UIPasteboard.general.string = s
        Haptics.success()
        model.showToast(message)
    }
}
