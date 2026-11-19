// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// A link to one Pocket AMP running the Onyx firmware.
///
/// The real implementation is the CoreBluetooth `BLEMIDITransport` in the app target; `SimulatedUnit`
/// (OnyxKit) implements the same protocol in software so the app can run in the simulator and in tests.
///
/// Threading: the whole protocol is main-actor isolated; callbacks are delivered on the main actor.
@MainActor
public protocol OnyxTransport: AnyObject {
    /// What the status line shows ("Pocket AMP", the peripheral's name ...).
    var displayName: String { get }
    /// True for Bluetooth: the editor then waits 4 ms between channel messages, uses longer reply timeouts
    /// (8 s instead of 1.5 s) and refuses the USB-only features (NAM upload, flash backup, firmware update).
    var isBLE: Bool { get }
    /// Largest SysEx payload per upload chunk (the web editor: 100 over Bluetooth, 200 over USB).
    var uploadChunk: Int { get }

    /// A complete SysEx reply `F0 ... F7` from the unit (BLE-MIDI already unframed).
    var onFrame: (([UInt8]) -> Void)? { get set }
    /// The link went away (peer disconnected, Bluetooth switched off ...). Not called by `close()`.
    var onClose: (() -> Void)? { get set }

    /// One channel message (`Cn pp` or `Bn cc vv`, 2 or 3 bytes). The BLE transport wraps it in one BLE-MIDI packet.
    func send(message: [UInt8]) async throws
    /// One whole SysEx frame `F0 ... F7`. The BLE transport splits it into BLE-MIDI packets and paces them (6 ms).
    func send(frame: [UInt8]) async throws
    /// Tear the link down. Does not call `onClose`.
    func close()
}

public enum OnyxLinkError: Error, LocalizedError, Equatable {
    case notConnected
    case timeout(String)
    case refused(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .timeout(let s): return s
        case .refused(let s): return s
        case .protocolError(let s): return s
        }
    }
}
