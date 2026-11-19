// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The connect sheet: Bluetooth state, the units found, tap to connect.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var scanner: any BLEScanning { model.scanner }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    content
                } header: {
                    Text("Pocket AMP")
                } footer: {
                    Text("Switch the unit on and keep it near. It must run the Onyx firmware.")
                }
                if let err = model.connectError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.bad)
                            .accessibilityLabel(Text("Error: \(err)"))
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onAppear { model.connectError = nil; scanner.startScan() }
        .onDisappear { scanner.stopScan() }
    }

    @ViewBuilder private var content: some View {
        switch scanner.bluetoothState {
        case .poweredOff:
            notice("Bluetooth is off", "Turn on Bluetooth in Control Center or Settings.", icon: "antenna.radiowaves.left.and.right.slash")
        case .unauthorized:
            notice("Bluetooth access is denied", "Allow Bluetooth for Onyx Editor in Settings > Privacy & Security > Bluetooth.", icon: "lock.slash")
            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                .frame(minHeight: 44)
        case .unsupported:
            notice("Bluetooth is not available on this device", "", icon: "xmark.circle")
        case .unknown, .poweredOn:
            if scanner.devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching for your Pocket AMP…").foregroundStyle(Palette.mid)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
            ForEach(scanner.devices) { d in
                Button {
                    Task { await model.connect(d) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hifispeaker.fill").foregroundStyle(Palette.accent).accessibilityHidden(true)
                        Text(d.name).foregroundStyle(Palette.text)
                        Spacer()
                        if model.connectingID == d.id {
                            ProgressView()
                            Text("Connecting…").font(.footnote).foregroundStyle(Palette.mid)
                        } else {
                            SignalBars(rssi: d.rssi)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .disabled(model.connectingID != nil)
                .accessibilityHint(Text("Connects to this unit"))
            }
        }
    }

    private func notice(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Palette.mid)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
