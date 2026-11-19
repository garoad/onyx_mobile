// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// Settings > MIDI Commands (for foot controllers): how to map a pedal, then every command the unit understands.
/// Compact width: a list that pushes the detail. Regular width (iPad): list and detail side by side.
struct MIDIHelpView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: String?
    @State private var width: CGFloat = 0

    /// Two columns when the screen is wide enough (iPad); a form sheet reports a compact size class, so the width decides.
    private var sideBySide: Bool { width >= 700 }

    private var results: [MIDICommand] { MIDICommandCatalog.filter(query) }

    var body: some View {
        Group {
            if sideBySide {
                HStack(spacing: 0) {
                    list.frame(width: 400)
                    Divider()
                    detail.frame(maxWidth: .infinity)
                }
            } else {
                list.navigationDestination(for: MIDICommand.self) { MIDICommandDetail(command: $0) }
            }
        }
        .background(Palette.bg)
        .background(GeometryReader { geo in
            Color.clear.onAppear { width = geo.size.width }.onChange(of: geo.size.width) { _, w in width = w }
        })
        .navigationTitle("MIDI Commands")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search: name, CC 21, 127 ..."))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = MIDICommandCatalog.plainText()
                    Haptics.success()
                    model.showToast(String(localized: "Copied the whole list"))
                } label: { Label("Copy all", systemImage: "doc.on.doc") }
                ShareLink(item: MIDICommandCatalog.plainText(), subject: Text("Pocket AMP MIDI commands")) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        List(selection: sideBySide ? $selection : .constant(nil)) {
            if query.isEmpty {
                Section { PedalGuideView() } header: { Text("How to map a pedal") }
                ForEach(MIDICommandCatalog.groups) { group in
                    Section {
                        let commands = MIDICommandCatalog.commands(in: group)
                        // 80 Program Changes would bury everything else: fold them.
                        ForEach(commands.filter { $0.programNumber == nil }) { row($0) }
                        let programs = commands.filter { $0.programNumber != nil }
                        if !programs.isEmpty {
                            DisclosureGroup("Program Change P01 to P80 (\(programs.count))") {
                                ForEach(programs) { row($0) }
                            }
                            .frame(minHeight: 44)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(group.title)).font(.subheadline.weight(.semibold)).textCase(nil).foregroundStyle(Palette.text)
                            Text(L(group.intro)).font(.footnote).textCase(nil).foregroundStyle(Palette.mid)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Section { ForEach(results) { row($0) } } header: { Text("\(results.count) found") }
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private func row(_ c: MIDICommand) -> some View {
        if sideBySide {
            MIDICommandRow(command: c).tag(c.id)
        } else {
            NavigationLink(value: c) { MIDICommandRow(command: c) }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selection, let c = MIDICommandCatalog.command(id: id) {
            ScrollView { MIDICommandDetail(command: c, embedded: true) }
        } else {
            ContentUnavailableView("Select a command", systemImage: "pianokeys", description: Text("Its bytes, value rule and notes appear here."))
        }
    }
}

struct MIDICommandRow: View {
    let command: MIDICommand

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(L(command.title)).font(.body.weight(.medium)).foregroundStyle(Palette.text)
                if command.status != .implemented { StatusBadge(status: command.status) }
            }
            Text("\(command.label) · \(command.hexString)")
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.accent)
            Text(command.summary).font(.footnote).foregroundStyle(Palette.mid).lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: MIDICommandStatus

    var body: some View {
        let text: LocalizedStringKey = status == .notImplemented ? "Not implemented" : "No effect"
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.onColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(status == .notImplemented ? Palette.bad : Palette.accent, in: Capsule())
    }
}

/// The expandable "how to map a pedal" sections at the top of the list.
private struct PedalGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(MIDIPedalGuide.intro)).font(.subheadline).foregroundStyle(Palette.mid)
            DisclosureGroup("Connecting and channel") {
                ForEach(MIDIPedalGuide.sections.prefix(3)) { guideBlock($0) }
            }
            DisclosureGroup("Tips for common setups") {
                ForEach(MIDIPedalGuide.mappingTips) { guideBlock($0) }
            }
            DisclosureGroup("Value rules") {
                ForEach(MIDIConnectionFacts.valueRules, id: \.self) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(r.messages)).font(.subheadline.weight(.semibold))
                        Text(L(r.rule)).font(.footnote).foregroundStyle(Palette.mid)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            DisclosureGroup("Reading the list") {
                ForEach(MIDIPedalGuide.sections.dropFirst(3)) { guideBlock($0) }
            }
        }
        .padding(.vertical, 4)
    }

    private func guideBlock(_ s: GuideSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(s.title)).font(.subheadline.weight(.semibold))
            Text(L(s.body)).font(.footnote).foregroundStyle(Palette.mid).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
