// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import CoreBluetooth
import Dispatch
import Foundation
import OnyxKit

/// BLE-MIDI link to one Pocket AMP (`openBle` of the web editor). Created by `BLEScanner.connect`, which owns the
/// `CBCentralManager`; the scanner forwards disconnects to `linkLost()`. Call `close()` when done: the scanner keeps
/// the transport (and so the connection) alive until then.
///
/// The NSObject `CBPeripheralDelegate` callbacks arrive on the main queue (the central's queue); they hop into the
/// main actor with `assumeIsolated`.
@MainActor
final class BLEMIDITransport: NSObject, OnyxTransport, CBPeripheralDelegate, BLEPacketSink {
    static let serviceUUID = CBUUID(string: BLEMIDI.serviceUUID)
    static let characteristicUUID = CBUUID(string: BLEMIDI.characteristicUUID)
    /// The web editor's packet size, the BLE minimum payload (ATT MTU 23 - 3); the unit's reader takes any size,
    /// but only 20 is proven against it.
    static let packetMax = 20

    let displayName: String
    let isBLE = true
    let uploadChunk = 100
    var onFrame: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?

    private let peripheral: CBPeripheral
    private let cancelConnection: @MainActor () -> Void
    private var characteristic: CBCharacteristic?
    private var unframer = BLEMIDI.Unframer()
    private var scheduler: BLEWriteScheduler!
    private var setupDone: ((Error?) -> Void)?
    private var packetMax = BLEMIDITransport.packetMax
    private var epoch = DispatchTime.now().uptimeNanoseconds
    private var ready = false
    private var closed = false

    init(peripheral: CBPeripheral, name: String, cancelConnection: @escaping @MainActor () -> Void) {
        self.peripheral = peripheral
        self.displayName = name
        self.cancelConnection = cancelConnection
        super.init()
        scheduler = BLEWriteScheduler(sink: self)
        peripheral.delegate = self
    }

    // MARK: setup (driven by BLEScanner)

    /// Discover the service and characteristic and enable notifications; `done` fires once the unit confirmed them.
    func start(_ done: @escaping (Error?) -> Void) {
        setupDone = done
        peripheral.discoverServices([Self.serviceUUID])
    }

    private func finishSetup(_ error: Error?) {
        guard let done = setupDone else { return }
        setupDone = nil
        done(error.map { Self.linkError($0) })
    }

    private func setupFailed(_ message: String) { finishSetup(OnyxLinkError.protocolError(message)) }

    // MARK: OnyxTransport

    func send(message: [UInt8]) async throws {
        guard !message.isEmpty else { return }
        try await enqueue([BLEMIDI.frames(message, chunkMax: packetMax, timestamp: timestamp())[0]], paced: false)
    }

    func send(frame: [UInt8]) async throws {
        try await enqueue(BLEMIDI.frames(frame, chunkMax: packetMax, timestamp: timestamp()), paced: true)
    }

    func close() {
        guard !closed else { return }
        closed = true
        onClose = nil
        teardown(OnyxLinkError.notConnected)
        cancelConnection()
    }

    /// The scanner saw the peripheral disconnect (or Bluetooth go away).
    func linkLost() {
        guard !closed else { return }
        closed = true
        teardown(OnyxLinkError.notConnected)
        let callback = onClose
        onClose = nil
        callback?()
    }

    private func teardown(_ error: Error) {
        ready = false
        scheduler.failAll(error)
        finishSetup(error)
        unframer.reset()
        onFrame = nil
    }

    // MARK: writing

    private func timestamp() -> Int { Int((DispatchTime.now().uptimeNanoseconds - epoch) / 1_000_000) & 0x1FFF }

    private func enqueue(_ packets: [[UInt8]], paced: Bool) async throws {
        guard ready, !closed else { throw OnyxLinkError.notConnected }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            scheduler.enqueue(packets: packets, paced: paced) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    var canWritePacket: Bool { ready && peripheral.state == .connected && peripheral.canSendWriteWithoutResponse }

    func writePacket(_ packet: [UInt8]) {
        guard let characteristic else { return }
        peripheral.writeValue(Data(packet), for: characteristic, type: .withoutResponse)
    }

    private static func linkError(_ e: Error) -> Error {
        e is OnyxLinkError ? e : OnyxLinkError.protocolError("Bluetooth: " + e.localizedDescription)
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { return finishSetup(error) }
            guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                return setupFailed("The device has no BLE-MIDI service")
            }
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            if let error { return finishSetup(error) }
            guard let ch = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
                return setupFailed("The device has no BLE-MIDI characteristic")
            }
            let room = peripheral.maximumWriteValueLength(for: .withoutResponse)
            guard room >= 8 else { return setupFailed("The Bluetooth link is too narrow for MIDI (\(room) bytes)") }
            packetMax = min(room, Self.packetMax)
            characteristic = ch
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == Self.characteristicUUID, setupDone != nil else { return }
            if let error { return finishSetup(error) }
            guard characteristic.isNotifying else { return setupFailed("The device did not enable notifications") }
            unframer.reset()
            epoch = DispatchTime.now().uptimeNanoseconds
            ready = true
            finishSetup(nil)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard ready, error == nil, let data = characteristic.value else { return }
            for frame in unframer.push([UInt8](data)) { onFrame?(frame) }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated { scheduler.sinkBecameReady() }
    }
}
