// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = ThemeChoice.system

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.settingsPath) {
            Form {
                connectionSection
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                }
                Section {
                    NavigationLink(value: SettingsRoute.midiHelp) {
                        Label("MIDI Commands (for foot controllers)", systemImage: "pianokeys").frame(minHeight: 44)
                    }
                } header: {
                    Text("MIDI pedal help")
                } footer: {
                    Text("Every message a MIDI foot controller can send to the Pocket AMP, with examples to copy.")
                }
                Section("Diagnostics") {
                    NavigationLink(value: SettingsRoute.log) {
                        Label("Log", systemImage: "text.alignleft").frame(minHeight: 44)
                    }
                }
                AboutSection()
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .midiHelp: MIDIHelpView()
                case .log: LogView()
                }
            }
        }
        .presentationDetents([.large])
        .modifier(PageSizing())
    }

    @ViewBuilder private var connectionSection: some View {
        let session = model.session
        Section("Connection") {
            if session.isConnected {
                LabeledContent("Device", value: session.uiDeviceName)
                if !session.buildCode.isEmpty { LabeledContent("Firmware build", value: session.buildCode) }
                Toggle("Live sync", isOn: Binding(get: { session.uiLiveSync }, set: { session.uiLiveSync = $0 }))
                    .frame(minHeight: 44)
                Button("Disconnect", role: .destructive) {
                    model.disconnect()
                    dismiss()
                }
                .frame(minHeight: 44)
            } else {
                Text("Not connected").foregroundStyle(Palette.mid)
                Button("Connect") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.showConnect = true }
                }
                .frame(minHeight: 44)
            }
        }
        if session.isConnected {
            Section { } footer: { Text("Live sync reads the unit every 1.5 s so changes made on the unit show here.") }
        }
    }
}

private struct AboutSection: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: version)
            Text("Based on the Onyx Web Editor by 28spawn (GPL-3.0)")
            if let url = URL(string: "https://github.com/28spawn/Pocket-Onyx") {
                Link(destination: url) {
                    Label("github.com/28spawn/Pocket-Onyx", systemImage: "link").frame(minHeight: 44)
                }
            }
            Text("Onyx Editor for iOS is free software, licensed under the GNU General Public License, version 3 only. You may copy, change and share it under the same terms.")
                .font(.footnote)
                .foregroundStyle(Palette.mid)
        }
    }
}

#if DEBUG
#Preview("Settings") { PreviewHost { SettingsView() } }
#endif

/// A wide sheet on iPad (iOS 18 and later); older systems keep the form sheet.
private struct PageSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.presentationSizing(.page) } else { content }
    }
}
