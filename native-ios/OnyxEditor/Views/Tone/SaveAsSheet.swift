// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// Save As: copies the sound of one preset into another preset number under a new name.
struct SaveAsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let source: Int

    @State private var name = ""
    @State private var destination: Int?
    @State private var confirmOverwrite = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var savedTo: Int?
    @State private var savedName = ""
    @State private var detent = PresentationDetent.large
    @FocusState private var nameFocused: Bool

    private var session: OnyxSession { model.session }
    private static let factoryCount = 40

    private var sourceName: String {
        if let s = session.state, s.preset == source { return s.name }
        return session.uiPresetInfo(source)?.name ?? ""
    }

    private var includesLiveEdits: Bool { session.state?.preset == source }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { destination != nil && !trimmedName.isEmpty && !saving && !session.busy && session.isConnected }

    var body: some View {
        NavigationStack {
            Group {
                if let savedTo { savedView(savedTo) } else { form }
            }
            .background(Palette.bg)
            .navigationTitle("Save As…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedTo == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .task {
            if name.isEmpty { name = PresetCopy.suggestedName(for: sourceName) }
            await session.uiLoadPresetSummaries()
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceCard
                nameField
                destinationSection
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text("Error: \(errorText)"))
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .confirmationDialog(overwriteTitle, isPresented: $confirmOverwrite, titleVisibility: .visible) {
            Button("Overwrite", role: .destructive) { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sound in this slot is replaced and cannot be restored.")
        }
    }

    private var sourceCard: some View {
        Panel {
            SectionTitle("Source")
            HStack(spacing: 10) {
                Text(presetLabel(source)).font(.title3.monospaced().weight(.semibold)).foregroundStyle(Palette.accent)
                Text(sourceName.isEmpty ? "-" : sourceName).font(.title3.weight(.semibold)).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            if includesLiveEdits {
                Label("Unsaved changes on the unit are included", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.mid)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Name")
            HStack {
                TextField("Name of the copy", text: $name)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .onChange(of: name) { _, v in
                        if v.count > PresetRecord.maxNameLength { name = String(v.prefix(PresetRecord.maxNameLength)) }
                    }
                Text("\(name.count)/\(PresetRecord.maxNameLength)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(name.count >= PresetRecord.maxNameLength ? Palette.accent : Palette.mid)
                    .accessibilityLabel(Text("\(name.count) of \(PresetRecord.maxNameLength) characters"))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(nameFocused ? Palette.accent : Palette.line))
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Copy to")
                Spacer()
                if session.uiIsLoadingSummaries {
                    ProgressView(value: session.summaryProgress).frame(width: 90)
                        .accessibilityLabel(Text("Reading preset names"))
                        .accessibilityValue(Text("\(Int(session.summaryProgress * 100)) percent"))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(0..<PresetRecord.count, id: \.self) { i in cell(i) }
            }
        }
    }

    private func cell(_ i: Int) -> some View {
        let info = session.uiPresetInfo(i)
        let isSource = i == source
        let selected = destination == i
        let factory = i < Self.factoryCount
        let title = info.map { $0.isEmpty ? String(localized: "EMPTY") : $0.name } ?? "…"
        return Button {
            Haptics.tick()
            destination = i
            errorText = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(presetLabel(i)).font(.footnote.monospaced().weight(.bold))
                    if factory { Image(systemName: "lock.fill").font(.caption2).accessibilityHidden(true) }
                    Spacer(minLength: 0)
                    if isSource { Text("SOURCE").font(.caption2.weight(.bold)) }
                }
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(info?.isEmpty == true ? Palette.mid : Palette.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected ? Palette.accent.opacity(0.22) : Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 2 : 1))
            .opacity(isSource ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSource || saving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(presetLabel(i)), \(title)\(factory ? ", " + String(localized: "factory slot") : "")"))
        .accessibilityHint(isSource ? Text("This is the source") : Text("Choose as the destination"))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                nameFocused = false
                if let d = destination, needsConfirmation(d) { confirmOverwrite = true } else { Task { await save() } }
            } label: {
                HStack {
                    if saving { ProgressView().tint(Palette.onColor) }
                    if let d = destination { Text("Save to \(presetLabel(d))").font(.headline) } else { Text("Choose a destination").font(.headline) }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
            .padding(16)
        }
        .background(.bar)
    }

    // MARK: Logic

    private func needsConfirmation(_ d: Int) -> Bool {
        if d < Self.factoryCount { return true }
        guard let info = session.uiPresetInfo(d) else { return true }
        return !info.isEmpty
    }

    private var overwriteTitle: String {
        guard let d = destination else { return "" }
        if let info = session.uiPresetInfo(d), !info.isEmpty, !info.name.isEmpty { return String(localized: "Overwrite \(presetLabel(d)) \"\(info.name)\"?") }
        return String(localized: "Overwrite \(presetLabel(d))?")
    }

    private func save() async {
        guard let d = destination else { return }
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            let finalName = trimmedName
            try await session.uiCopyPreset(from: source, to: d, name: finalName)
            savedName = finalName
            savedTo = d
            Haptics.success()
            model.showToast(String(localized: "Saved as \(presetLabel(d)) \(finalName)"))
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }

    private func savedView(_ d: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Palette.ok).accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Saved as \(presetLabel(d))").font(.title2.weight(.semibold))
                Text(savedName).font(.title3).foregroundStyle(Palette.mid)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            VStack(spacing: 10) {
                Button {
                    session.uiSelectPreset(d)
                    dismiss()
                } label: {
                    Text("Go to \(presetLabel(d))").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Stay on \(presetLabel(source))") { dismiss() }
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Save As") {
    PreviewHost { Color.clear.sheet(isPresented: .constant(true)) { SaveAsSheet(source: 6) } }
}
#endif
