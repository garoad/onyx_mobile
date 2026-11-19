// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import CoreBluetooth
import Foundation
import Observation
import OnyxKit

/// Finds Pocket AMPs (BLE-MIDI service) and opens `BLEMIDITransport` links.
///
/// The `CBCentralManager` is created on the first `startScan()` / `connect`, so the Bluetooth permission prompt
/// appears when the user taps Connect and not at launch (NSBluetoothAlwaysUsageDescription is set in the project).
/// `bluetoothState` reads the system authorization first and never creates the manager just to look.
@MainActor @Observable
final class BLEScanner: NSObject, CBCentralManagerDelegate, BLEScanning {
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var bluetoothState: BluetoothAvailability = .unknown

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var seen: [UUID: Seen] = [:]
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var active: [UUID: WeakTransport] = [:]

    private struct Seen {
        var peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var lastSeen: Date
    }

    private struct WeakTransport { weak var transport: BLEMIDITransport? }

    private final class Pending {
        let id: UUID
        let peripheral: CBPeripheral
        var transport: BLEMIDITransport?
        var timeout: Task<Void, Never>?
        private var continuation: CheckedContinuation<any OnyxTransport, Error>?
        init(id: UUID, peripheral: CBPeripheral, continuation: CheckedContinuation<any OnyxTransport, Error>) {
            self.id = id; self.peripheral = peripheral; self.continuation = continuation
        }
        func resume(_ result: Result<any OnyxTransport, Error>) {
            timeout?.cancel()
            guard let c = continuation else { return }
            continuation = nil
            c.resume(with: result)
        }
    }

    static let connectTimeout: Duration = .seconds(10)
    private static let staleAfter: TimeInterval = 8
    private static let unknownRSSI = -127   // a peripheral the system already holds: no advertisement, no RSSI
    private static let service = CBUUID(string: BLEMIDI.serviceUUID)

    override init() { super.init() }

    // MARK: BLEScanning

    func startScan() {
        scanning = true
        ensureCentral()
        beginScanIfPossible()
        guard maintenance == nil else { return }
        maintenance = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.prune()
            }
        }
    }

    func stopScan() {
        scanning = false
        maintenance?.cancel()
        maintenance = nil
        if central?.isScanning == true { central?.stopScan() }
    }

    func connect(_ d: DiscoveredDevice) async throws -> any OnyxTransport {
        ensureCentral()
        guard bluetoothState == .poweredOn else { throw Self.unavailable(bluetoothState) }
        guard pending == nil else { throw OnyxLinkError.refused("Another connection is in progress") }
        guard let entry = seen[d.id] else { throw OnyxLinkError.refused("\(d.name) is no longer in range") }
        stopScan()
        let central = self.central!
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<any OnyxTransport, Error>) in
            let p = Pending(id: d.id, peripheral: entry.peripheral, continuation: c)
            p.timeout = Task { @MainActor [weak self, weak p] in
                try? await Task.sleep(for: Self.connectTimeout)
                guard !Task.isCancelled, let self, let p, self.pending === p else { return }
                self.fail(p, OnyxLinkError.timeout("Timed out connecting to \(d.name)"))
            }
            pending = p
            central.connect(entry.peripheral)
        }
    }

    // MARK: state

    private func ensureCentral() {
        guard central == nil else { return }
        switch CBManager.authorization {
        case .denied, .restricted: bluetoothState = .unauthorized; return
        default: break
        }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private static func map(_ s: CBManagerState) -> BluetoothAvailability {
        switch s {
        case .poweredOn: return .poweredOn
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        default: return .unknown
        }
    }

    private static func unavailable(_ s: BluetoothAvailability) -> OnyxLinkError {
        switch s {
        case .poweredOff: return .refused("Bluetooth is turned off")
        case .unauthorized: return .refused("Bluetooth access is denied: allow it in Settings")
        case .unsupported: return .refused("Bluetooth is not available on this device")
        default: return .refused("Bluetooth is not ready yet")
        }
    }

    // MARK: scanning

    private func beginScanIfPossible() {
        guard scanning, let central, central.state == .poweredOn else { return }
        // Duplicates on: that is how the RSSI stays current; the list is rebuilt at most twice a second.
        if !central.isScanning {
            central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        adoptConnected()
        publish(force: true)
    }

    /// The unit may already be connected to the system (as a MIDI device): it does not advertise then.
    private func adoptConnected() {
        guard let central else { return }
        for p in central.retrieveConnectedPeripherals(withServices: [Self.service]) {
            var e = seen[p.identifier] ?? Seen(peripheral: p, name: Self.name(of: p, nil), rssi: Self.unknownRSSI, lastSeen: .now)
            e.peripheral = p
            e.lastSeen = .now
            seen[p.identifier] = e
        }
    }

    private func prune() {
        guard scanning else { return }
        adoptConnected()
        let cutoff = Date.now.addingTimeInterval(-Self.staleAfter)
        seen = seen.filter { $0.value.lastSeen >= cutoff || $0.key == pending?.id || active[$0.key]?.transport != nil }
        publish(force: false)
    }

    private func publish(force: Bool) {
        let now = Date.now
        guard force || now.timeIntervalSince(lastPublish) >= 0.5 else { return }
        lastPublish = now
        let list = seen.map { DiscoveredDevice(id: $0.key, name: $0.value.name, rssi: $0.value.rssi) }
            .sorted { ($0.rssi, $1.name, $0.id.uuidString) > ($1.rssi, $0.name, $1.id.uuidString) }
        if list != devices { devices = list }
    }

    private static func name(of p: CBPeripheral, _ adv: [String: Any]?) -> String {
        let n = (adv?[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
        return (n?.isEmpty == false ? n : nil) ?? "BLE MIDI"
    }

    // MARK: connection outcome

    private func fail(_ p: Pending, _ error: Error) {
        guard pending === p else { return }
        pending = nil
        if let t = p.transport { t.close() } else { central?.cancelPeripheralConnection(p.peripheral) }
        p.resume(.failure(error))
        beginScanIfPossible()
    }

    private func linkEnded(_ id: UUID) {
        if let t = active.removeValue(forKey: id)?.transport { t.linkLost() }
    }

    // MARK: CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothState = Self.map(central.state)
            if central.state == .poweredOn {
                beginScanIfPossible()
                return
            }
            // CoreBluetooth drops every connection without a disconnect callback.
            if let p = pending { fail(p, Self.unavailable(bluetoothState)) }
            for id in Array(active.keys) { linkEnded(id) }
            seen = [:]
            devices = []
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let value = RSSI.intValue
            guard value != 127 else { return }   // "RSSI not available"
            let name = Self.name(of: peripheral, advertisementData)
            let isNew = seen[peripheral.identifier] == nil || seen[peripheral.identifier]?.name != name
            seen[peripheral.identifier] = Seen(peripheral: peripheral, name: name, rssi: value, lastSeen: .now)
            publish(force: isNew)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let p = pending, p.peripheral.identifier == peripheral.identifier else {
                central.cancelPeripheralConnection(peripheral)   // not ours (a timed-out attempt)
                return
            }
            let id = peripheral.identifier
            let transport = BLEMIDITransport(peripheral: peripheral, name: seen[id]?.name ?? Self.name(of: peripheral, nil)) { [weak self] in
                self?.active[id] = nil
                self?.central?.cancelPeripheralConnection(peripheral)
            }
            p.transport = transport
            active[id] = WeakTransport(transport: transport)
            transport.start { [weak self, weak p] error in
                guard let self, let p, self.pending === p else { return }
                if let error {
                    self.active[id] = nil
                    self.fail(p, error)
                } else {
                    self.pending = nil
                    p.resume(.success(transport))
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard let p = pending, p.peripheral.identifier == peripheral.identifier else { return }
            fail(p, OnyxLinkError.refused("Could not connect: " + (error?.localizedDescription ?? "unknown error")))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            if let p = pending, p.id == id {
                active[id] = nil
                fail(p, OnyxLinkError.refused("The device disconnected while connecting"))
            } else {
                linkEnded(id)
            }
        }
    }
}
