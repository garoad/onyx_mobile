// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OnyxKit

struct DiscoveredDevice: Identifiable, Hashable {
    var id: UUID
    var name: String
    var rssi: Int
}

enum BluetoothAvailability { case unknown, poweredOn, poweredOff, unauthorized, unsupported }

/// What the connect flow needs from Bluetooth. `BLEScanner` (CoreBluetooth) is the real one, `SimulatedScanner` the simulator's.
@MainActor
protocol BLEScanning: AnyObject {
    var devices: [DiscoveredDevice] { get }
    var bluetoothState: BluetoothAvailability { get }
    func startScan()
    func stopScan()
    func connect(_ d: DiscoveredDevice) async throws -> any OnyxTransport
}
