// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import OnyxKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case tone, global, groove, presets, library

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .tone: return "Tone"
        case .global: return "Global"
        case .groove: return "Groove"
        case .presets: return "Presets"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .tone: return "waveform"
        case .global: return "slider.horizontal.3"
        case .groove: return "metronome"
        case .presets: return "list.number"
        case .library: return "books.vertical"
        }
    }
}

enum SettingsRoute: Hashable { case midiHelp, log }

/// Save As, from the preset `source` (its stored sound; the live sound when it is the preset on the unit).
struct SaveAsRequest: Identifiable {
    let source: Int
    var id: Int { source }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

@MainActor @Observable
final class AppModel {
    let session = OnyxSession()
    let scanner: any BLEScanning

    var section: AppSection = .tone
    var showConnect = false
    var showSettings = false
    var settingsPath: [SettingsRoute] = []
    var saveAsRequest: SaveAsRequest?
    private(set) var toast: Toast?
    private(set) var connectingID: UUID?
    var connectError: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let arguments: [String]

    init(scanner: (any BLEScanning)? = nil, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        if let scanner {
            self.scanner = scanner
        } else {
            #if targetEnvironment(simulator)
            self.scanner = SimulatedScanner()
            #else
            self.scanner = arguments.contains("-simulatedUnit") ? SimulatedScanner() : BLEScanner()
            #endif
        }
    }

    /// Called once when the first view appears.
    func start() async {
        #if DEBUG
        await DebugLaunch.apply(self, arguments: arguments)
        #endif
    }

    func connect(_ d: DiscoveredDevice) async {
        guard connectingID == nil else { return }
        connectingID = d.id
        connectError = nil
        defer { connectingID = nil }
        do {
            let transport = try await scanner.connect(d)
            await session.uiConnect(transport)
            if session.isConnected {
                session.startLiveSync()
                scanner.stopScan()
                showConnect = false
                showToast(String(localized: "Connected to \(d.name)"))
            } else {
                connectError = session.uiStatusText
            }
        } catch {
            connectError = error.localizedDescription
        }
    }

    func disconnect() {
        session.disconnect()
        showToast(String(localized: "Disconnected"))
    }

    func showToast(_ text: String, error: Bool = false) {
        toastTask?.cancel()
        toast = Toast(text: text, isError: error)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func presentSaveAs(source: Int) { saveAsRequest = SaveAsRequest(source: source) }
}

/// "P07"
func presetLabel(_ index: Int) -> String { "P" + String(format: "%02d", index + 1) }
