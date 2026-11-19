// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// Where the scheduler puts packets: the CoreBluetooth transport, or a fake in a check.
@MainActor
protocol BLEPacketSink: AnyObject {
    /// False while the link's write-without-response queue is full (`canSendWriteWithoutResponse`).
    var canWritePacket: Bool { get }
    func writePacket(_ packet: [UInt8])
}

/// Ordered queue of BLE-MIDI packets with the web editor's pacing (`sendFrame`: a pause after every packet of a
/// SysEx frame) and flow control (stop while the sink is full, go on at `sinkBecameReady()`). No CoreBluetooth in here.
@MainActor
final class BLEWriteScheduler {
    typealias Timer = (_ ms: Int, _ fire: @escaping @MainActor () -> Void) -> Void

    private final class Job {
        let packets: [[UInt8]], paced: Bool, completion: (Error?) -> Void
        var next = 0
        init(_ packets: [[UInt8]], _ paced: Bool, _ completion: @escaping (Error?) -> Void) {
            self.packets = packets; self.paced = paced; self.completion = completion
        }
    }

    private weak var sink: BLEPacketSink?
    private let pacingMs: Int
    private let timer: Timer
    private var queue: [Job] = []
    private var waiting = false         // inside the pause after a paced packet
    private var pumping = false         // completions may enqueue again
    private var generation = 0          // a timer from before `failAll` must not wake the new queue

    var pendingJobs: Int { queue.count }

    init(sink: BLEPacketSink, pacingMs: Int = 6, timer: Timer? = nil) {
        self.sink = sink; self.pacingMs = pacingMs; self.timer = timer ?? Self.sleepTimer
    }

    static let sleepTimer: Timer = { ms, fire in
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            fire()
        }
    }

    /// `completion(nil)` after the last packet is written (and, when `paced`, after the pause that follows it, like the web editor).
    func enqueue(packets: [[UInt8]], paced: Bool, completion: @escaping (Error?) -> Void) {
        guard !packets.isEmpty else { completion(nil); return }
        queue.append(Job(packets, paced, completion))
        pump()
    }

    func sinkBecameReady() { pump() }

    func failAll(_ error: Error) {
        generation += 1
        waiting = false
        let dead = queue
        queue = []
        for job in dead { job.completion(error) }
    }

    private func paceElapsed(_ gen: Int) {
        guard gen == generation else { return }
        waiting = false
        if let job = queue.first, job.next == job.packets.count { finishFirst() }
        pump()
    }

    private func finishFirst() {
        let job = queue.removeFirst()
        job.completion(nil)
    }

    private func pump() {
        guard !pumping else { return }
        pumping = true
        defer { pumping = false }
        while !waiting, let sink, let job = queue.first {
            guard sink.canWritePacket else { return }
            sink.writePacket(job.packets[job.next])
            job.next += 1
            if job.paced {
                waiting = true
                let gen = generation
                timer(pacingMs) { [weak self] in self?.paceElapsed(gen) }
            } else if job.next == job.packets.count {
                finishFirst()
            }
        }
    }
}
