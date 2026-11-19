// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// iPhone: a tab bar. iPad (regular width): a sidebar. Both show the status line, the connect button and the Settings gear.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("theme") private var theme = ThemeChoice.system

    var body: some View {
        @Bindable var model = model
        Group {
            if sizeClass == .regular { splitLayout } else { tabLayout }
        }
        .tint(Palette.accent)
        .overlay { ToastOverlay() }
        .sheet(isPresented: $model.showConnect) { ConnectView().environment(model) }
        .sheet(isPresented: $model.showSettings) { SettingsView().environment(model) }
        .sheet(item: $model.saveAsRequest) { SaveAsSheet(source: $0.source).environment(model) }
        .preferredColorScheme(theme.scheme)
        .task { await model.start() }
    }

    private var tabLayout: some View {
        @Bindable var model = model
        return TabView(selection: $model.section) {
            ForEach(AppSection.allCases) { s in
                NavigationStack {
                    sectionView(s)
                        .toolbar { toolbar }
                        .navigationTitle(s.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .background(Palette.bg)
                }
                .tabItem { Label(s.title, systemImage: s.icon) }
                .tag(s)
            }
        }
    }

    private var splitLayout: some View {
        @Bindable var model = model
        return NavigationSplitView {
            List(AppSection.allCases, selection: Binding<AppSection?>(get: { model.section }, set: { if let v = $0 { model.section = v } })) { s in
                Label(s.title, systemImage: s.icon).frame(minHeight: 44).tag(s)
            }
            .navigationTitle("Onyx Editor")
            .safeAreaInset(edge: .bottom) {
                StatusButton().padding(12)
            }
        } detail: {
            NavigationStack {
                sectionView(model.section)
                    .toolbar { toolbar }
                    .navigationTitle(model.section.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .background(Palette.bg)
            }
        }
    }

    @ViewBuilder private func sectionView(_ s: AppSection) -> some View {
        VStack(spacing: 0) {
            if sizeClass != .regular { StatusButton().padding(.horizontal, 16).padding(.top, 8) }
            switch s {
            case .tone: ToneView()
            case .global: GlobalView()
            case .groove: GrooveView()
            case .presets: PresetsView()
            case .library: LibraryView()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// The web editor's status line as a button: green dot and the unit's name, or a Connect prompt.
struct StatusButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connected = model.session.isConnected
        Button {
            model.showConnect = !connected
            if connected { model.showSettings = true }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(connected ? Palette.ok : Palette.dim).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(connected ? String(localized: "Connected: \(model.session.uiDeviceName)") : String(localized: "Not connected"))
                    .font(.footnote)
                    .foregroundStyle(connected ? Palette.ok : Palette.mid)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !connected { Text("Connect").font(.footnote.weight(.semibold)) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(connected ? "Opens the settings" : "Opens the connect screen"))
    }
}
