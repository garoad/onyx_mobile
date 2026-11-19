// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation
import Observation

/// One preset as the destination picker of "Save as" shows it.
public struct PresetSummary: Equatable, Sendable, Identifiable {
    public var index: Int
    public var name: String
    public var isEmpty: Bool
    public var seq: UInt32
    public var id: Int { index }

    public init(index: Int, name: String, isEmpty: Bool, seq: UInt32) {
        self.index = index; self.name = name; self.isEmpty = isEmpty; self.seq = seq
    }

    init(index: Int, record r: PresetRecord) { self.init(index: index, name: r.name, isEmpty: r.isEmpty, seq: r.seq) }
}

/// What `uploadReliable` found out about the unit.
public enum UploadResult: Equatable, Sendable {
    /// Every byte was acknowledged and the unit stored the transfer.
    case acknowledged
    /// An older firmware that does not acknowledge uploads: nothing was sent, the caller sends the blind frames (`legacyUpload`).
    case legacy
}

/// The editor's connection logic (the part of the web editor that is not DOM): a request/reply link to the unit, the state record, the throttled
/// controls, live sync and the preset actions. It talks to any `OnyxTransport`: the CoreBluetooth one on a device, `SimulatedUnit` elsewhere.
@MainActor
@Observable
public final class OnyxSession {
    /// Every delay and timeout of the session; the defaults are the web editor's. Tests pass short ones.
    public struct Timing: Sendable {
        public var usbReply = 1.5
        public var bleReply = 8.0
        /// A slider value is sent this long after the last change (`throttled`).
        public var throttle = 0.040
        /// Pause after each channel message over Bluetooth.
        public var bleGap = 0.004
        public var poll = 1.5
        public var refreshAfterMove = 0.3
        /// Refresh after a preset change / save sent from here.
        public var refreshAfterAction = 0.15
        public var beginTimeout = 2.5
        public var chunkTimeout = 2.0
        public var presetReadTimeout = 3.0
        public var beginRetryDelay = 0.25
        public var chunkRetryDelay = 0.3
        /// After an acknowledged preset upload: the unit has already rewritten its flash bank.
        public var settleAcked = 0.06
        public var settleLegacy = 0.35
        public var legacyFrameDelay = 0.025
        public var legacyEdgeDelay = 0.15

        public init() {}
        public static let standard = Timing()
        /// Milliseconds instead of seconds, for tests.
        public static var fast: Timing {
            var t = Timing()
            t.usbReply = 0.25; t.bleReply = 0.5; t.throttle = 0.01; t.bleGap = 0; t.poll = 0.05; t.refreshAfterMove = 0.02
            t.refreshAfterAction = 0.01; t.beginTimeout = 0.1; t.chunkTimeout = 0.08; t.presetReadTimeout = 0.15
            t.beginRetryDelay = 0.005; t.chunkRetryDelay = 0.005; t.settleAcked = 0; t.settleLegacy = 0.01
            t.legacyFrameDelay = 0; t.legacyEdgeDelay = 0
            return t
        }
    }

    // MARK: Observable state

    public private(set) var state: DeviceState?
    public private(set) var ampNames: [String] = []
    public private(set) var cabNames: [String] = []
    public private(set) var firstAmp = 20
    public private(set) var firstCab = 20
    /// Counts the name lists read; a model picker rebuilds itself when it changes.
    public private(set) var namesRevision = 0
    public private(set) var buildCode = ""
    public private(set) var log: [String] = []
    public private(set) var status = "not connected"
    public private(set) var isConnected = false
    public private(set) var isBLE = false
    public private(set) var transportName = ""
    /// A long operation (upload, preset reads) is running: the live-sync poll and `refresh()` stand back.
    public var busy: Bool { busyDepth > 0 }
    public private(set) var isLiveSyncing = false
    /// The destination picker's data: one entry per preset, nil = not read (yet, or unreadable).
    public private(set) var presetSummaries = [PresetSummary?](repeating: nil, count: PresetRecord.count)
    /// 0...1 while `loadPresetSummaries` runs.
    public private(set) var summaryProgress = 0.0
    public private(set) var isLoadingSummaries = false

    public let timing: Timing

    // MARK: Machinery

    @ObservationIgnored private var transport: (any OnyxTransport)?
    private var busyDepth = 0
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var generation = 0

    private struct Waiter {
        var id: Int
        var type: UInt8
        var cont: CheckedContinuation<[UInt8], Error>
    }
    @ObservationIgnored private var waiter: Waiter?
    @ObservationIgnored private var waiterTimeout: Task<Void, Never>?
    @ObservationIgnored private var lockHeld = false
    @ObservationIgnored private var lockQueue: [(id: Int, cont: CheckedContinuation<Void, Error>)] = []

    @ObservationIgnored private var shortTail: Task<Void, Never>?
    @ObservationIgnored private var pending: [EditedControl: (token: Int, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var editing: Set<EditedControl> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshFailed = false
    @ObservationIgnored private var unreadable: Set<Int> = []

    public init(timing: Timing = .standard) { self.timing = timing }

    // MARK: Log

    public func addLog(_ m: String) {
        log.append(m)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    /// "P01  Name", the way the editor names the preset on the unit.
    public static func presetLabel(_ s: DeviceState) -> String {
        "P" + String(format: "%02d", s.preset + 1) + "  " + (s.name.isEmpty ? "(empty)" : s.name)
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    }

    private func withBusy<T>(_ body: () async throws -> T) async rethrows -> T {
        busyDepth += 1
        defer { busyDepth -= 1 }
        return try await body()
    }

    // MARK: Connect / disconnect

    /// `connect`: names of the amps and cabinets, the build code, the state record. Returns false (and says why in `status`) when the unit does not answer.
    @discardableResult
    public func connect(_ t: any OnyxTransport) async -> Bool {
        if transport != nil { teardown(closeTransport: true, status: "not connected") }
        transport = t
        isBLE = t.isBLE
        transportName = t.displayName
        t.onFrame = { [weak self] f in self?.deliver(f) }
        t.onClose = { [weak self] in self?.linkClosed(t) }
        status = "connecting: " + t.displayName
        addLog("connecting to " + t.displayName)
        let gen = generation
        do {
            try await readNames(kind: 0)
            try await readNames(kind: 1)
            if let d = try? await request(81, [255, 0], type: 0x61), d.count >= 5 {
                buildCode = String(String.UnicodeScalarView(d[5..<min(d.count, 5 + Int(d[3]))].map { Unicode.Scalar($0) }))
                addLog("firmware build " + buildCode)
            } else { buildCode = "" }
            guard gen == generation else { return false }
            addLog("\(ampNames.filter { !$0.isEmpty }.count) amp models, \(cabNames.filter { !$0.isEmpty }.count) cabinets")
            isConnected = true
            status = "connected: " + t.displayName + (buildCode.isEmpty ? "" : " (build \(buildCode))")
            await performRefresh()
            if let s = state {
                let label = Self.presetLabel(s)
                status += "  |  " + label
                addLog("preset on the unit: " + label)
            }
            return true
        } catch {
            guard gen == generation else { return false }
            addLog("connect: " + error.localizedDescription)
            teardown(closeTransport: true, status: error.localizedDescription)
            return false
        }
    }

    /// Ends the link from this side.
    public func disconnect() {
        guard transport != nil else { return }
        teardown(closeTransport: true, status: "not connected")
        addLog("disconnected")
    }

    private func linkClosed(_ t: any OnyxTransport) {
        guard transport === t else { return }
        teardown(closeTransport: false, status: "not connected")
        addLog("link closed")
    }

    private func teardown(closeTransport: Bool, status s: String) {
        generation += 1
        stopLiveSync()
        pending.values.forEach { $0.task.cancel() }
        pending = [:]
        editing = []
        refreshTask?.cancel(); refreshTask = nil
        failWaiter(nil, OnyxLinkError.notConnected)
        let t = transport
        transport = nil
        t?.onFrame = nil; t?.onClose = nil
        if closeTransport { t?.close() }
        isConnected = false
        isBLE = false
        status = s
        state = nil
        presetSummaries = [PresetSummary?](repeating: nil, count: PresetRecord.count)
        unreadable = []
        summaryProgress = 0
        refreshFailed = false
    }

    // MARK: Request / reply

    private func deliver(_ frame: [UInt8]) {
        guard let r = SysEx.parseReply(frame), let w = waiter, w.type == r.type else { return }
        waiter = nil
        waiterTimeout?.cancel()
        w.cont.resume(returning: r.data)
    }

    /// Fails the waiter with the given id (nil = whichever is waiting).
    private func failWaiter(_ id: Int?, _ error: Error) {
        guard let w = waiter, id == nil || w.id == id else { return }
        waiter = nil
        waiterTimeout?.cancel()
        w.cont.resume(throwing: error)
    }

    private func acquireLock() async throws {
        if !lockHeld { lockHeld = true; return }
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in lockQueue.append((id, c)) }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let i = self.lockQueue.firstIndex(where: { $0.id == id }) else { return }
                self.lockQueue.remove(at: i).cont.resume(throwing: CancellationError())
            }
        }
    }

    private func releaseLock() {
        if lockQueue.isEmpty { lockHeld = false } else { lockQueue.removeFirst().cont.resume() }
    }

    /// `request`: send a command frame and wait for the reply of the given type. One request is on the wire at a time (the others queue).
    /// Throws `OnyxLinkError.timeout` after `timeout` seconds (default 1.5 USB / 8 Bluetooth).
    public func request(_ cmd: UInt8, _ payload: [UInt8] = [], type: UInt8, timeout: TimeInterval? = nil) async throws -> [UInt8] {
        try await acquireLock()
        defer { releaseLock() }
        guard let t = transport else { throw OnyxLinkError.notConnected }
        let limit = timeout ?? (t.isBLE ? timing.bleReply : timing.usbReply)
        let frame = try SysEx.buildFrame(cmd: cmd, payload: payload)
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[UInt8], Error>) in
                waiter = Waiter(id: id, type: type, cont: c)
                waiterTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.failWaiter(id, OnyxLinkError.timeout("no reply to command \(cmd)"))
                }
                Task { [weak self] in
                    do { try await t.send(frame: frame) } catch { self?.failWaiter(id, error) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failWaiter(id, CancellationError()) }
        }
    }

    /// Channel messages in the order given, three bytes each (a BLE-MIDI packet or a USB MIDI message), 4 ms apart over Bluetooth. Never throws; a failure is logged.
    /// Calls are serialised, so the messages of one NRPN are never mixed with another's.
    public func sendShort(_ bytes: [UInt8]) async {
        guard let t = transport else { return }
        let prev = shortTail
        let gap = t.isBLE ? timing.bleGap : 0
        let job = Task { [weak self] in
            await prev?.value
            var i = 0
            while i < bytes.count {
                do { try await t.send(message: Array(bytes[i..<min(i + 3, bytes.count)])) }
                catch { self?.addLog("send failed: " + error.localizedDescription); return }
                if gap > 0 { try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000)) }
                i += 3
            }
        }
        shortTail = job
        await job.value
    }

    /// One whole SysEx frame (the legacy blind upload, `request` is the normal path).
    public func sendFrame(_ frame: [UInt8]) async throws {
        guard let t = transport else { throw OnyxLinkError.notConnected }
        try await t.send(frame: frame)
    }

    // MARK: Names and state

    /// `readNames`: the amp (kind 0) or cabinet (kind 1) type names; an empty name is a deleted capture or cabinet whose number stays.
    public func readNames(kind: Int) async throws {
        var out: [String] = []
        var first = 20
        var start = 0, total = 1
        while start < total {
            let d = try await request(81, [UInt8(kind), UInt8(start)], type: 0x61)
            guard d.count >= 5 else { throw OnyxLinkError.protocolError("short names reply") }
            total = Int(d[1]); first = Int(d[4])
            let n = Int(d[3])
            for i in 0..<n where d.count >= 21 + i * 16 {
                out.append(String(String.UnicodeScalarView(d[(5 + i * 16)..<(21 + i * 16)].filter { $0 != 0 }.map { Unicode.Scalar($0) })))
            }
            if n == 0 { break }
            start += n
        }
        if kind == 0 { ampNames = out; firstAmp = first } else { cabNames = out; firstCab = first }
        namesRevision += 1
    }

    /// Reads both name lists again (after a capture or cabinet was stored, deleted or renamed).
    public func refreshNames() async {
        do { try await readNames(kind: 0); try await readNames(kind: 1) } catch { addLog("names: " + error.localizedDescription) }
    }

    /// The state record of the unit (cmd 80).
    public func fetchState() async throws -> DeviceState {
        let d = try await request(80, [], type: 0x60)
        guard let s = DeviceState.decode(d) else { throw OnyxLinkError.protocolError("unreadable state record") }
        return s
    }

    /// `refresh`: re-reads the state. Does nothing while an operation is running; a control that is being dragged keeps its value.
    public func refresh() async {
        guard transport != nil, !busy else { return }
        await performRefresh()
    }

    private func performRefresh() async {
        let gen = generation
        do {
            var s = try await fetchState()
            guard gen == generation else { return }
            if let old = state {
                for c in editing.union(pending.keys) { s.adopt(c, from: old) }
            }
            if state != s { state = s }
            refreshFailed = false
        } catch is CancellationError {
        } catch {
            if !refreshFailed { addLog("state: " + error.localizedDescription) }
            refreshFailed = true
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
            self.refreshTask = nil
        }
    }

    // MARK: Live sync

    /// Polls the state every 1.5 s (skipped while an operation runs or a control is being dragged).
    public func startLiveSync() {
        guard pollTask == nil, transport != nil else { return }
        isLiveSyncing = true
        let interval = timing.poll
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if !self.busy && self.editing.isEmpty && self.pending.isEmpty { await self.refresh() }
            }
        }
    }

    public func stopLiveSync() {
        pollTask?.cancel(); pollTask = nil
        isLiveSyncing = false
    }

    // MARK: Controls held by a finger

    /// The control is being dragged: a state refresh leaves its value alone (the web editor's `dragging`).
    public func beginEditing(_ c: EditedControl) { editing.insert(c) }
    public func endEditing(_ c: EditedControl) { editing.remove(c) }

    /// Waits until every throttled value and queued message has been sent (and a scheduled refresh has run).
    public func settle() async {
        while let e = pending.values.first { await e.task.value }
        await shortTail?.value
        await refreshTask?.value
    }

    private func throttled(_ c: EditedControl, _ action: @escaping @MainActor () async -> Void) {
        pending[c]?.task.cancel()
        nextID += 1
        let token = nextID
        let delay = timing.throttle
        let task = Task { [weak self] in
            defer { if let s = self, s.pending[c]?.token == token { s.pending[c] = nil } }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
        pending[c] = (token, task)
    }

    // MARK: Throttled controls (sliders and pickers; the last value wins, sent 40 ms after the last change)

    /// A knob of a slot, 0...100 %.
    public func setKnob(_ slot: Slot, _ k: Int, _ value: Int) {
        guard (0..<6).contains(k) else { return }
        let v = max(0, min(100, value))
        state?.slots[slot.rawValue].knobs[k] = v
        throttled(.knob(slot, k)) { [weak self] in await self?.sendShort(MIDIControl.nrpn(module: slot.module, param: 0x60 + k, v)) }
    }

    public func setPresetVolume(_ value: Int) {
        let v = max(0, min(100, value))
        state?.presetVol = v
        throttled(.presetVolume) { [weak self] in await self?.sendShort(MIDIControl.nrpn(module: 10, param: 0, v, raw: true)) }
    }

    /// A setting of the Global tab (and the output level); `raw` is the number of NRPN module 8 (`GlobalParam.value(in:)`).
    public func setGlobal(_ p: GlobalParam, _ raw: Int) {
        let v = p.spec.kind.clamp(raw)
        state?.assign(p, raw: v)
        throttled(.global(p)) { [weak self] in await self?.sendShort(MIDIControl.nrpn(module: 8, param: p.rawValue, v, raw: true)) }
    }

    /// A Groove Station setting; `value` is what the UI shows (the BPM 40...260), `GrooveParam.wire` turns it into the number sent.
    public func setGroove(_ p: GrooveParam, _ value: Int) {
        let v = p.spec.kind.clamp(value)
        state?.assign(p, wire: p.wire(v))
        throttled(.groove(p)) { [weak self] in await self?.sendShort(MIDIControl.nrpn(module: 9, param: p.rawValue, p.wire(v), raw: true)) }
    }

    // MARK: Direct actions

    /// CC 28+n, the module's on/off switch.
    public func setSlotEnabled(_ slot: Slot, _ on: Bool) async {
        state?.slots[slot.rawValue].on = on
        await sendShort(MIDIControl.cc(28 + slot.module, on ? MIDIControl.on : MIDIControl.off))
    }

    /// The model / type of a slot: `index` is the type number (the entry of `ampNames` / `cabNames` / the fixed tables).
    public func setModel(_ slot: Slot, _ index: Int) async {
        state?.slots[slot.rawValue].type = index
        if slot == .cab { state?.userCab = false }
        await sendShort(MIDIControl.nrpn(module: slot.module, param: 0x40, index + 0x20, raw: true))
    }

    /// One of the four STOMP-mode keys (VOL-, VOL+, <, >): `module` is the NRPN module number (`Stomp.moduleNames`).
    public func setStompKey(_ key: Int, module: Int) async {
        guard (0..<4).contains(key), let s = Slot(module: module) else { return }
        state?.stomp[key] = s.rawValue
        await sendShort(MIDIControl.nrpn(module: 10, param: 3 + key, module, raw: true))
    }

    public func setGroovePlaying(_ on: Bool) async {
        state?.setFlag(4, on)
        await sendShort(MIDIControl.cc(86, on ? MIDIControl.on : MIDIControl.off))
    }

    /// CC 85: opens (or closes) the tuner on the unit.
    public func setTuner(_ on: Bool) async {
        state?.setFlag(2, on)
        await sendShort(MIDIControl.cc(85, on ? MIDIControl.on : MIDIControl.off))
    }

    public func nextPreset() async { await stepPreset(80) }
    public func previousPreset() async { await stepPreset(81) }

    private func stepPreset(_ cc: Int) async {
        await settle()
        await sendShort(MIDIControl.cc(cc, MIDIControl.on))
        scheduleRefresh(after: timing.refreshAfterAction)
    }

    /// Program change: the unit loads P(pc + 1).
    public func selectPreset(_ pc: Int) async {
        guard (0..<PresetRecord.count).contains(pc) else { return }
        await settle()
        await sendShort(MIDIControl.pc(pc))
        scheduleRefresh(after: timing.refreshAfterAction)
    }

    /// CC 88: the sound on the unit goes into the current preset.
    public func saveCurrent() async {
        await settle()
        let index = state?.preset
        await sendShort(MIDIControl.cc(88, MIDIControl.on))
        addLog("save sent (CC 88)")
        if let i = index { invalidateSummary(i) }
        scheduleRefresh(after: timing.refreshAfterAction)
    }

    /// The editor's drag and drop of a block: the order changes here at once, the unit follows (NRPN module 10 parameter 7), the state is read again after 300 ms.
    public func moveSlot(_ slot: Slot, to: Int) async {
        guard let s = state, let from = s.order.firstIndex(of: slot.rawValue), from != to, (0...7).contains(to) else { return }
        state?.order = MIDIControl.chainMove(s.order, slot: slot.rawValue, to: to)
        await sendShort(MIDIControl.chainMoveMessage(slot: slot.rawValue, to: to))
        addLog("\(slot.name) moved to position \(to + 1)")
        scheduleRefresh(after: timing.refreshAfterMove)
    }

    // MARK: Presets: read / write

    /// `cmd 83`: one stored preset. nil = the unit says it cannot read it, or the record is not valid. Throws when the unit does not answer.
    public func readPreset(_ i: Int) async throws -> PresetRecord? {
        guard (0..<PresetRecord.count).contains(i) else { throw OnyxLinkError.refused("preset number out of range") }
        let d = try await request(83, [UInt8(i)], type: 0x63, timeout: timing.presetReadTimeout)
        guard d.count >= 2 + PresetRecord.size, d[1] == 0 else { return nil }
        return PresetRecord(record: Array(d[2..<(2 + PresetRecord.size)]))
    }

    /// Stores a record in slot `i` the way the editor's save does (upload target 0): the slot's own seq + 1, EMPTY cleared. Does not read it back.
    public func writePreset(_ i: Int, _ record: PresetRecord) async throws {
        guard (0..<PresetRecord.count).contains(i) else { throw OnyxLinkError.refused("preset number out of range") }
        try await withBusy { try await storePreset(record, slot: i) }
        invalidateSummary(i)
    }

    private func storePreset(_ record: PresetRecord, slot: Int) async throws {
        let bytes = record.encode()
        let r = try await uploadReliable(bytes, target: PresetCopy.uploadTarget, slot: UInt8(slot))
        if r == .legacy { try await legacyUpload(bytes, target: PresetCopy.uploadTarget, slot: UInt8(slot)) }
        try await sleep(r == .legacy ? timing.settleLegacy : timing.settleAcked)
    }

    // MARK: Upload

    /// `uploadReliable`: cmd 25 (begin) and cmd 34 (chunks), each acknowledged with the number of bytes the unit holds; a lost chunk is asked for and resent from there.
    /// Returns `.legacy` when the unit does not answer the begin (an older firmware): the caller then sends the blind frames with `legacyUpload`.
    public func uploadReliable(_ bytes: [UInt8], target: UInt8, slot: UInt8 = 0, chunk: Int? = nil, onProgress: ((Double) -> Void)? = nil) async throws -> UploadResult {
        guard let t = transport else { throw OnyxLinkError.notConnected }
        let chunk = chunk ?? t.uploadChunk
        let n = bytes.count
        func u24(_ a: [UInt8]) -> Int { Int(a[0]) | Int(a[1]) << 8 | Int(a[2]) << 16 }
        func checked(_ a: [UInt8]) throws -> [UInt8] {
            guard a.count >= 4 else { throw OnyxLinkError.protocolError("short upload acknowledgement") }
            return a
        }
        var ack: [UInt8]
        var tries = 0
        while true {
            do {
                ack = try checked(await request(25, [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), target, slot], type: 0x64, timeout: timing.beginTimeout))
            } catch is CancellationError { throw CancellationError()
            } catch OnyxLinkError.notConnected { throw OnyxLinkError.notConnected
            } catch { return .legacy }
            if ack[3] != 2 { break }
            if tries >= 5 { throw OnyxLinkError.refused("the unit refused the transfer") }
            tries += 1
            try await sleep(timing.beginRetryDelay)          // refused at the begin: the audio core still holds a swap, done within about 100 ms
        }
        var off = u24(ack), bad = 0
        while off < n {
            let part = Array(bytes[off..<min(off + chunk, n)])
            do {
                ack = try checked(await request(34, part, type: 0x64, timeout: timing.chunkTimeout))
            } catch is CancellationError { throw CancellationError()
            } catch OnyxLinkError.notConnected { throw OnyxLinkError.notConnected
            } catch {
                do { ack = try checked(await request(34, [], type: 0x64, timeout: timing.chunkTimeout)) }      // no answer: ask what it holds
                catch is CancellationError { throw CancellationError()
                } catch OnyxLinkError.notConnected { throw OnyxLinkError.notConnected
                } catch {
                    bad += 1
                    if bad > 8 { throw OnyxLinkError.protocolError("the unit stopped answering") }
                    try await sleep(timing.chunkRetryDelay)
                    continue
                }
            }
            let got = u24(ack)
            if ack[3] == 1 { onProgress?(1); return .acknowledged }
            if ack[3] == 2 { throw OnyxLinkError.refused("the unit refused the transfer (it was incomplete or not valid)") }
            if ack[3] == 3 { throw OnyxLinkError.refused("the unit has no transfer open") }
            if got != off + part.count {
                bad += 1
                if bad > 12 { throw OnyxLinkError.protocolError("the unit keeps losing data") }
            }
            off = got                                        // resume from what the unit really holds
            onProgress?(Double(off) / Double(n))
        }
        return .acknowledged
    }

    /// `uploadFrames`: the blind frames of an older firmware: begin, chunks, commit.
    public static func uploadFrames(_ bytes: [UInt8], target: UInt8, slot: UInt8, chunk: Int) throws -> [[UInt8]] {
        let n = bytes.count
        var fr = [try SysEx.buildFrame(cmd: 25, payload: [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), target, slot])]
        var i = 0
        while i < n { fr.append(try SysEx.buildFrame(cmd: 34, payload: Array(bytes[i..<min(i + chunk, n)]))); i += chunk }
        fr.append(try SysEx.buildFrame(cmd: 48))
        return fr
    }

    /// The legacy path after `uploadReliable` returned `.legacy`: every frame once, paced, not acknowledged.
    public func legacyUpload(_ bytes: [UInt8], target: UInt8, slot: UInt8) async throws {
        guard let t = transport else { throw OnyxLinkError.notConnected }
        let frames = try Self.uploadFrames(bytes, target: target, slot: slot, chunk: t.uploadChunk)
        for (k, f) in frames.enumerated() {
            try await sendFrame(f)
            try await sleep(k == 0 || k == frames.count - 1 ? timing.legacyEdgeDelay : timing.legacyFrameDelay)
        }
    }

    // MARK: Save as

    /// The name of a copy as the unit stores it: printable ASCII only (anything else becomes "_"), trimmed, at most 23 characters.
    public static func cleanPresetName(_ s: String) -> String {
        let mapped = String(String.UnicodeScalarView(s.unicodeScalars.map { (0x20...0x7E).contains($0.value) ? $0 : "_" }))
        return String(mapped.trimmingCharacters(in: .whitespaces).prefix(PresetRecord.maxNameLength))
    }

    /// Save as: copies the sound of preset `from` into preset `to` (both 0...79) under `name`, and reads the destination back to prove it.
    ///
    /// The stored record of the source is the base. When the source is the preset that is on the unit now, the live state is laid over it first, so an edit that
    /// was not saved yet travels with the copy. The destination is written like the editor's save (cmd 25 target 0): EMPTY is cleared and its seq grows by one.
    /// Throws `OnyxLinkError.refused` for bad numbers or a name that is empty, when the source cannot be read, or when the destination does not read back as sent.
    /// The unit does not load the copy; call `selectPreset(to)` for that.
    @discardableResult
    public func copyPreset(from: Int, to: Int, name: String) async throws -> PresetRecord {
        let range = 0..<PresetRecord.count
        guard range.contains(from), range.contains(to) else { throw OnyxLinkError.refused("preset numbers must be 1 to 80") }
        guard from != to else { throw OnyxLinkError.refused("choose a different preset than the source") }
        let clean = Self.cleanPresetName(name)
        guard !clean.isEmpty else { throw OnyxLinkError.refused("give the copy a name") }
        guard transport != nil else { throw OnyxLinkError.notConnected }
        let label = { (i: Int) in "P" + String(format: "%02d", i + 1) }
        return try await withBusy {
            await settle()
            let live = try await fetchState()
            state = live
            guard let stored = try await readPreset(from) else { throw OnyxLinkError.refused("\(label(from)) cannot be read from the unit") }
            let intended = PresetCopy.record(base: stored, live: live.preset == from ? live : nil, name: clean)
            try await storePreset(intended, slot: to)
            guard let back = try await readPreset(to) else { throw OnyxLinkError.refused("\(label(to)) cannot be read back after the copy") }
            guard PresetCopy.sameSound(intended, back) else { throw OnyxLinkError.refused("\(label(to)) did not read back as sent") }
            presetSummaries[to] = PresetSummary(index: to, record: back)
            unreadable.remove(to)
            addLog("copied \(label(from)) to \(label(to)) as \(clean)")
            return back
        }
    }

    // MARK: Preset list for the destination picker

    /// Reads all 80 presets (name, EMPTY, seq) into `presetSummaries`, with `summaryProgress`. Ones that are cached for this connection are not read again
    /// (`force` reads them all); unreadable ones are skipped. Cancelling the calling Task stops it and keeps what was read; three unanswered reads in a row stop it too.
    public func loadPresetSummaries(force: Bool = false) async {
        guard transport != nil, !isLoadingSummaries else { return }
        isLoadingSummaries = true
        busyDepth += 1
        let gen = generation
        defer { isLoadingSummaries = false; busyDepth -= 1 }
        if force { presetSummaries = [PresetSummary?](repeating: nil, count: PresetRecord.count); unreadable = [] }
        summaryProgress = 0
        var silent = 0
        for i in 0..<PresetRecord.count {
            if Task.isCancelled || gen != generation { return }
            if presetSummaries[i] == nil && !unreadable.contains(i) {
                do {
                    if let r = try await readPreset(i) { presetSummaries[i] = PresetSummary(index: i, record: r) } else { unreadable.insert(i) }
                    silent = 0
                } catch is CancellationError { return
                } catch OnyxLinkError.notConnected { return
                } catch {
                    silent += 1
                    if silent >= 3 { addLog("preset list: the unit stopped answering"); return }
                }
            }
            if gen == generation { summaryProgress = Double(i + 1) / Double(PresetRecord.count) }
        }
    }

    /// Forgets what was read of one preset (it is read again by the next `loadPresetSummaries`).
    public func invalidateSummary(_ i: Int) {
        guard presetSummaries.indices.contains(i) else { return }
        presetSummaries[i] = nil
        unreadable.remove(i)
    }
}
