// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import OnyxKit

/// Lists one fake unit that connects to `SimulatedUnit`: the simulator has no Bluetooth, and `-simulatedUnit` runs it on a device too.
@MainActor @Observable
final class SimulatedScanner: BLEScanning {
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var bluetoothState: BluetoothAvailability = .poweredOn
    @ObservationIgnored private var scan: Task<Void, Never>?

    private static let unitID = UUID(uuidString: "5A1B2C3D-0000-4000-8000-0000000000A1")!

    func startScan() {
        scan?.cancel()
        scan = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.devices = [DiscoveredDevice(id: Self.unitID, name: "Pocket AMP (Simulator)", rssi: -58)]
        }
    }

    func stopScan() { scan?.cancel() }

    func connect(_ d: DiscoveredDevice) async throws -> any OnyxTransport {
        try await Task.sleep(for: .milliseconds(400))
        return SimulatedUnit(name: "Pocket AMP (Simulator)", isBLE: false)
    }
}
