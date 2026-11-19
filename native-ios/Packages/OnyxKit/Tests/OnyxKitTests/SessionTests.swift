// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

@MainActor
final class SessionTests: XCTestCase {
    private func makePair(ble: Bool = false, connect: Bool = true) async -> (OnyxSession, SimulatedUnit) {
        let unit = SimulatedUnit(isBLE: ble)
        let s = OnyxSession(timing: .fast)
        if connect {
            let ok = await s.connect(unit)
            XCTAssertTrue(ok, s.status)
        }
        return (s, unit)
    }

    private func messages(_ u: SimulatedUnit, startingWith b: [UInt8]) -> Int {
        u.receivedMessages.filter { $0.starts(with: b) }.count
    }

    // MARK: connect

    func testConnectReadsNamesBuildCodeAndState() async {
        let (s, u) = await makePair()
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.ampNames.count, 22)
        XCTAssertEqual(s.cabNames.count, 21)
        XCTAssertEqual(s.ampNames[0], "1 UK Clean")
        XCTAssertEqual(s.ampNames[20], "Fender NAM")
        XCTAssertEqual(s.cabNames[20], "Greenback IR")
        XCTAssertEqual(s.firstAmp, 20)
        XCTAssertEqual(s.firstCab, 20)
        XCTAssertEqual(s.buildCode, u.buildCode)
        XCTAssertEqual(s.namesRevision, 2)
        XCTAssertEqual(s.state, u.live)
        XCTAssertTrue(s.status.contains("P01  Clean Sparkle"), s.status)
        XCTAssertTrue(s.status.contains(u.buildCode))
    }

    func testConnectFailsAgainstASilentUnit() async {
        let u = SimulatedUnit(isBLE: false)
        u.isSilent = true
        let s = OnyxSession(timing: .fast)
        let ok = await s.connect(u)
        XCTAssertFalse(ok)
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(s.state)
        XCTAssertTrue(s.log.contains { $0.contains("no reply to command 81") }, s.log.joined(separator: "\n"))
    }

    func testRequestTimesOutWhenTheUnitGoesSilent() async {
        let (s, u) = await makePair()
        u.isSilent = true
        let t0 = Date()
        do {
            _ = try await s.request(80, [], type: 0x60)
            XCTFail("expected a timeout")
        } catch let e as OnyxLinkError {
            XCTAssertEqual(e, .timeout("no reply to command 80"))
        } catch { XCTFail("\(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        u.isSilent = false
        let d = try? await s.request(80, [], type: 0x60)
        XCTAssertEqual(d?.count, 128, "the next request works")
    }

    func testBleUsesTheLongTimeout() async {
        let (s, u) = await makePair(ble: true)
        u.isSilent = true
        let t0 = Date()
        _ = try? await s.request(80, [], type: 0x60)
        let dt = Date().timeIntervalSince(t0)
        XCTAssertGreaterThanOrEqual(dt, OnyxSession.Timing.fast.bleReply - 0.05)
        XCTAssertLessThan(dt, 3)
        XCTAssertEqual(OnyxSession.Timing.standard.bleReply, 8)
        XCTAssertEqual(OnyxSession.Timing.standard.usbReply, 1.5)
    }

    func testRequestsAreSerialised() async {
        let (s, _) = await makePair()
        async let a = s.request(80, [], type: 0x60)
        async let b = s.request(83, [3], type: 0x63)
        async let c = s.request(81, [0, 0], type: 0x61)
        let (ra, rb, rc) = try! await (a, b, c)
        XCTAssertEqual(ra.count, 128)
        XCTAssertEqual(rb[0], 3)
        XCTAssertEqual(rc[0], 0)
    }

    func testDisconnectFromTheUnitSide() async {
        let (s, u) = await makePair()
        s.startLiveSync()
        u.simulateDisconnect()
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(s.state)
        XCTAssertFalse(s.isLiveSyncing)
        XCTAssertEqual(s.status, "not connected")
        do { _ = try await s.request(80, [], type: 0x60); XCTFail() } catch { XCTAssertEqual(error as? OnyxLinkError, .notConnected) }
    }

    // MARK: setters

    func testSettersReachTheUnit() async {
        let (s, u) = await makePair()
        await s.setSlotEnabled(.rev, true)
        XCTAssertTrue(u.live.slots[Slot.rev.rawValue].on)
        await s.setSlotEnabled(.rev, false)
        XCTAssertFalse(u.live.slots[Slot.rev.rawValue].on)
        await s.setModel(.amp, 9)
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].type, 9)
        await s.setModel(.mod, 4)
        XCTAssertEqual(u.live.slots[Slot.mod.rawValue].type, 4)
        await s.setStompKey(1, module: 4)
        XCTAssertEqual(u.live.stomp[1], Slot.rev.rawValue)
        await s.setGroovePlaying(true)
        XCTAssertTrue(u.live.groovePlaying)
        await s.setTuner(true)
        XCTAssertTrue(u.live.tunerOpen)
        await s.setTuner(false)
        XCTAssertFalse(u.live.tunerOpen)

        s.setKnob(.amp, 2, 64)
        s.setPresetVolume(33)
        s.setGlobal(.inputGain, 20)
        s.setGlobal(.balance, 60)
        s.setGroove(.bpm, 200)
        s.setGroove(.drums, 0)
        await s.settle()
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[2], 64)
        XCTAssertEqual(u.live.presetVol, 33)
        XCTAssertEqual(u.live.g.inGain, 8)
        XCTAssertEqual(u.live.g.balance, 10)
        XCTAssertEqual(u.live.g.bpm, 200)
        XCTAssertEqual(u.live.g.drums, 0)
        await s.refresh()
        XCTAssertEqual(s.state, u.live)
        XCTAssertEqual(s.state?.g.bpm, 200)
    }

    func testSendShortSplitsIntoThreeByteMessages() async {
        let (s, u) = await makePair()
        await s.sendShort(MIDIControl.nrpn(module: 8, param: 3, 1, raw: true))
        XCTAssertEqual(u.receivedMessages.suffix(3).map { $0 }, [[0xB0, 99, 8], [0xB0, 98, 3], [0xB0, 6, 1]])
        await s.sendShort(MIDIControl.pc(4))
        XCTAssertEqual(u.receivedMessages.last, [0xC0, 4])
    }

    func testThrottleCollapsesToTheLastValue() async {
        let (s, u) = await makePair()
        for v in 10...60 { s.setKnob(.amp, 0, v) }
        XCTAssertEqual(s.state?.slots[Slot.amp.rawValue].knobs[0], 60, "the UI sees the value at once")
        XCTAssertEqual(messages(u, startingWith: [0xB0, 99, 1]), 0, "nothing sent yet")
        await s.settle()
        XCTAssertEqual(messages(u, startingWith: [0xB0, 99, 1]), 1, "one NRPN, not fifty")
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[0], 60)
        // two controls throttle independently
        s.setKnob(.amp, 1, 5); s.setKnob(.cab, 1, 6)
        await s.settle()
        XCTAssertEqual(u.live.slots[Slot.amp.rawValue].knobs[1], 5)
        XCTAssertEqual(u.live.slots[Slot.cab.rawValue].knobs[1], 6)
    }

    func testRefreshLeavesADraggedControlAlone() async {
        let (s, u) = await makePair()
        let c = EditedControl.knob(.amp, 0)
        s.beginEditing(c)
        s.setKnob(.amp, 0, 97)
        s.beginEditing(.presetVolume)
        let unitValue = u.live.slots[Slot.amp.rawValue].knobs[0]
        await s.refresh()          // the value is still pending: the unit has the old one
        XCTAssertEqual(s.state?.slots[Slot.amp.rawValue].knobs[0], 97)
        await s.settle()
        await s.refresh()
        XCTAssertEqual(s.state?.slots[Slot.amp.rawValue].knobs[0], 97)
        XCTAssertNotEqual(unitValue, 97)
        // the unit changes under the held control: still not taken over
        u.live.slots[Slot.amp.rawValue].knobs[0] = 3
        u.live.presetVol = 12
        await s.refresh()
        XCTAssertEqual(s.state?.slots[Slot.amp.rawValue].knobs[0], 97)
        XCTAssertNotEqual(s.state?.presetVol, 12, "held too")
        s.endEditing(c); s.endEditing(.presetVolume)
        await s.refresh()
        XCTAssertEqual(s.state?.slots[Slot.amp.rawValue].knobs[0], 3)
        XCTAssertEqual(s.state?.presetVol, 12)
    }

    func testLiveSyncPollsAndStandsBackWhileEditingOrBusy() async throws {
        let (s, u) = await makePair()
        s.startLiveSync()
        XCTAssertTrue(s.isLiveSyncing)
        u.live.outLevel = 61
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(s.state?.outLevel, 61, "the poll picked up the change")
        s.beginEditing(.global(.fizz))
        try await Task.sleep(nanoseconds: 80_000_000)       // a poll that was already on the wire finishes
        let before = u.receivedCommands.filter { $0 == 80 }.count
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(u.receivedCommands.filter { $0 == 80 }.count, before, "no polling while a control is held")
        s.endEditing(.global(.fizz))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(u.receivedCommands.filter { $0 == 80 }.count, before)
        s.stopLiveSync()
        XCTAssertFalse(s.isLiveSyncing)
        try await Task.sleep(nanoseconds: 80_000_000)       // a poll that was already on the wire finishes
        let after = u.receivedCommands.filter { $0 == 80 }.count
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(u.receivedCommands.filter { $0 == 80 }.count, after)
        s.disconnect()
    }

    // MARK: actions

    func testMoveSlotRoundTrip() async {
        let (s, u) = await makePair()
        await s.moveSlot(.rev, to: 0)
        XCTAssertEqual(s.state?.order, [7, 0, 1, 2, 3, 4, 5, 6], "optimistic at once")
        XCTAssertEqual(u.live.order, [7, 0, 1, 2, 3, 4, 5, 6])
        await s.settle()                                   // the refresh after the move
        XCTAssertEqual(s.state?.order, [7, 0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(s.state, u.live)
        await s.moveSlot(.rev, to: 7)
        await s.settle()
        XCTAssertEqual(s.state?.order, [0, 1, 2, 3, 4, 5, 6, 7])
        await s.moveSlot(.dyn, to: 0)                      // already there: nothing is sent
        XCTAssertEqual(messages(u, startingWith: [0xB0, 99, 10]), 2)
    }

    func testSelectPresetAndStepping() async {
        let (s, u) = await makePair()
        await s.selectPreset(12)
        await s.settle()
        XCTAssertEqual(u.live.preset, 12)
        XCTAssertEqual(s.state?.preset, 12)
        XCTAssertEqual(s.state?.name, u.presets[12].name)
        await s.nextPreset(); await s.settle()
        XCTAssertEqual(s.state?.preset, 13)
        await s.previousPreset(); await s.previousPreset(); await s.settle()
        XCTAssertEqual(s.state?.preset, 11)
        await s.selectPreset(80)
        XCTAssertEqual(u.live.preset, 11, "out of range is not sent")
    }

    func testSaveCurrent() async {
        let (s, u) = await makePair()
        s.setKnob(.amp, 0, 15)
        await s.saveCurrent()                              // settles the pending knob first
        await s.settle()
        XCTAssertEqual(PresetRecord.percent(q16: u.presets[0].params[2][0]), 15)
        XCTAssertEqual(u.presets[0].seq, 2)
        XCTAssertTrue(s.log.contains("save sent (CC 88)"))
    }

    // MARK: stored presets

    func testReadAndWritePreset() async throws {
        let (s, u) = await makePair()
        let p = try await s.readPreset(7)
        XCTAssertEqual(p, u.presets[7])
        let bad = try await s.readPreset(40)
        XCTAssertTrue(try XCTUnwrap(bad).isEmpty)
        do { _ = try await s.readPreset(80); XCTFail() } catch { XCTAssertEqual(error as? OnyxLinkError, .refused("preset number out of range")) }
        var r = try XCTUnwrap(p)
        r.name = "Rewritten"
        try await s.writePreset(7, r)
        XCTAssertEqual(u.presets[7].name, "Rewritten")
        XCTAssertEqual(u.presets[7].seq, 2)
        do { try await s.writePreset(-1, r); XCTFail() } catch { XCTAssertEqual(error as? OnyxLinkError, .refused("preset number out of range")) }
    }

    // MARK: uploadReliable

    func testUploadReliableRecoversFromADroppedChunk() async throws {
        let (s, u) = await makePair()
        let bytes = SimulatedFactory.record(3).encode()
        u.dropIncomingChunks = 1
        let r = try await s.uploadReliable(bytes, target: 0, slot: 66, chunk: 100)
        XCTAssertEqual(r, .acknowledged)
        XCTAssertEqual(u.presets[66].name, SimulatedFactory.record(3).name)
        XCTAssertFalse(u.presets[66].isEmpty)
        XCTAssertEqual(u.dropIncomingChunks, 0)
    }

    func testUploadReliableRetriesARefusedBeginAndGivesUp() async throws {
        let (s, u) = await makePair()
        let bytes = SimulatedFactory.record(4).encode()
        u.refuseBegins = 2
        var r = try await s.uploadReliable(bytes, target: 0, slot: 67)
        XCTAssertEqual(r, .acknowledged)
        XCTAssertEqual(u.refuseBegins, 0)
        u.refuseBegins = 100
        do { r = try await s.uploadReliable(bytes, target: 0, slot: 68); XCTFail() }
        catch { XCTAssertEqual(error as? OnyxLinkError, .refused("the unit refused the transfer")) }
    }

    func testUploadReliableReportsProgressAndRefusedRecords() async throws {
        let (s, u) = await makePair()
        var seen: [Double] = []
        let bytes = SimulatedFactory.record(4).encode()
        _ = try await s.uploadReliable(bytes, target: 0, slot: 69, chunk: 40) { seen.append($0) }
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen, seen.sorted())
        var bad = bytes
        bad[100] ^= 1
        do { _ = try await s.uploadReliable(bad, target: 0, slot: 69, chunk: 100); XCTFail() }
        catch { XCTAssertEqual(error as? OnyxLinkError, .refused("the unit refused the transfer (it was incomplete or not valid)")) }
        XCTAssertEqual(u.presets[69].seq, 2)
    }

    func testLegacyFirmwareFallsBackToBlindFrames() async throws {
        let (s, u) = await makePair()
        u.acknowledgesUploads = false
        var rec = SimulatedFactory.record(5)
        rec.name = "Legacy"
        try await s.writePreset(72, rec)
        XCTAssertEqual(u.presets[72].name, "Legacy")
        XCTAssertFalse(u.presets[72].isEmpty)
    }

    // MARK: Save as

    func testCopyEmptyDestinationBecomesSaved() async throws {
        let (s, u) = await makePair()
        let src = u.presets[0]
        XCTAssertTrue(u.presets[49].isEmpty)
        let r = try await s.copyPreset(from: 0, to: 49, name: "My Copy")
        let dest = u.presets[49]
        XCTAssertFalse(dest.isEmpty)
        XCTAssertEqual(dest.seq, 2)
        XCTAssertEqual(dest.name, "My Copy")
        XCTAssertTrue(PresetCopy.sameSound(dest, r))
        var expected = src
        expected.name = "My Copy"
        XCTAssertTrue(PresetCopy.sameSound(dest, expected), "same sound as the source")
        XCTAssertEqual(u.presets[0], src, "the source is not touched")
        XCTAssertEqual(s.presetSummaries[49]?.name, "My Copy")
        XCTAssertFalse(s.busy)
        XCTAssertEqual(u.live.preset, 0, "the unit does not switch to the copy")

        // copying over a saved slot bumps its own counter again
        _ = try await s.copyPreset(from: 1, to: 49, name: "Second")
        XCTAssertEqual(u.presets[49].seq, 3)
        XCTAssertEqual(u.presets[49].name, "Second")
    }

    func testCopyOfTheActivePresetCarriesTheUnsavedEdit() async throws {
        let (s, u) = await makePair()
        await s.selectPreset(2)
        await s.settle()
        s.setKnob(.amp, 0, 91)
        await s.setSlotEnabled(.rev, true)
        await s.setModel(.amp, 11)
        s.setPresetVolume(44)
        await s.moveSlot(.rev, to: 1)
        let storedAmp = PresetRecord.percent(q16: u.presets[2].params[2][0])
        XCTAssertNotEqual(storedAmp, 91)
        let r = try await s.copyPreset(from: 2, to: 60, name: "Edited")
        let dest = u.presets[60]
        XCTAssertEqual(PresetRecord.percent(q16: dest.params[2][0]), 91)
        XCTAssertEqual(dest.slotType[2], 11)
        XCTAssertEqual(dest.ampModel, 11)
        XCTAssertNotEqual(dest.slotEnableMask & (1 << 7), 0)
        XCTAssertEqual(dest.presetVol, 44)
        XCTAssertEqual(dest.slotOrder, [0, 7, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(r, dest)
        XCTAssertEqual(PresetRecord.percent(q16: u.presets[2].params[2][0]), storedAmp, "the source slot keeps its stored sound")
        XCTAssertEqual(u.presets[2].seq, 1)
    }

    func testCopyOfAnotherPresetIgnoresTheLiveEdit() async throws {
        let (s, u) = await makePair()
        s.setKnob(.amp, 0, 3)
        await s.settle()
        _ = try await s.copyPreset(from: 5, to: 70, name: "Other")
        XCTAssertTrue(PresetCopy.sameSound(u.presets[70], { var e = u.presets[5]; e.name = "Other"; return e }()))
    }

    func testCopyIsRefusedForBadArguments() async throws {
        let (s, u) = await makePair()
        let before = u.presets
        let cases: [(Int, Int, String)] = [(-1, 50, "x"), (0, 80, "x"), (80, 50, "x"), (0, -3, "x"), (4, 4, "x"), (0, 50, "   "), (0, 50, "")]
        for (a, b, n) in cases {
            do { _ = try await s.copyPreset(from: a, to: b, name: n); XCTFail("\(a) \(b) \(n)") }
            catch let e as OnyxLinkError { if case .refused = e {} else { XCTFail("\(e)") } }
        }
        XCTAssertEqual(u.presets, before)
        XCTAssertFalse(s.busy)
        let o = OnyxSession(timing: .fast)
        do { _ = try await o.copyPreset(from: 0, to: 50, name: "x"); XCTFail() } catch { XCTAssertEqual(error as? OnyxLinkError, .notConnected) }
    }

    func testCopyNameIsCleanedAndCut() async throws {
        let (s, u) = await makePair()
        _ = try await s.copyPreset(from: 0, to: 41, name: "  Caf\u{E9} \u{1F3B8} " + String(repeating: "x", count: 40))
        let n = u.presets[41].name
        XCTAssertEqual(n.count, 23)
        XCTAssertTrue(n.hasPrefix("Caf_ _"), n)
        XCTAssertEqual(OnyxSession.cleanPresetName("   "), "")
    }

    func testCopySurvivesADroppedChunkOverAChunkedLink() async throws {
        let unit = SimulatedUnit(isBLE: false, uploadChunk: 60)
        let s = OnyxSession(timing: .fast)
        let connected = await s.connect(unit)
        XCTAssertTrue(connected)
        unit.dropIncomingChunks = 1
        let r = try await s.copyPreset(from: 8, to: 79, name: "Chunky")
        XCTAssertEqual(unit.presets[79].name, "Chunky")
        XCTAssertEqual(r.name, "Chunky")
    }

    func testCopyFailsClearlyWhenTheDestinationDoesNotReadBackAsSent() async throws {
        let (s, u) = await makePair()
        u.acknowledgesUploads = false
        // an old firmware takes the blind frames; make the unit lose them all so the read-back differs
        u.dropIncomingChunks = 100
        do { _ = try await s.copyPreset(from: 0, to: 45, name: "Lost"); XCTFail("expected a refusal") }
        catch let e as OnyxLinkError { if case .refused(let m) = e { XCTAssertTrue(m.contains("P46"), m) } else { XCTFail("\(e)") } }
        XCTAssertTrue(u.presets[45].isEmpty)
    }

    func testCopyFailsWhenTheUnitStopsAnswering() async throws {
        let (s, u) = await makePair()
        u.isSilent = true
        do { _ = try await s.copyPreset(from: 0, to: 45, name: "Nope"); XCTFail() }
        catch { XCTAssertEqual(error as? OnyxLinkError, .timeout("no reply to command 80")) }
        XCTAssertFalse(s.busy)
    }

    // MARK: Preset list

    func testLoadPresetSummariesReadsAllAndCaches() async {
        let (s, u) = await makePair()
        await s.loadPresetSummaries()
        XCTAssertEqual(s.presetSummaries.compactMap { $0 }.count, 80)
        XCTAssertEqual(s.summaryProgress, 1)
        XCTAssertEqual(s.presetSummaries[0], PresetSummary(index: 0, name: "Clean Sparkle", isEmpty: false, seq: 1))
        XCTAssertEqual(s.presetSummaries[79]?.isEmpty, true)
        XCTAssertFalse(s.isLoadingSummaries)
        let reads = u.receivedCommands.filter { $0 == 83 }.count
        XCTAssertEqual(reads, 80)
        await s.loadPresetSummaries()
        XCTAssertEqual(u.receivedCommands.filter { $0 == 83 }.count, 80, "cached for this connection")
        s.invalidateSummary(3)
        await s.loadPresetSummaries()
        XCTAssertEqual(u.receivedCommands.filter { $0 == 83 }.count, 81, "only the invalidated one is read again")
        await s.loadPresetSummaries(force: true)
        XCTAssertEqual(u.receivedCommands.filter { $0 == 83 }.count, 161)
    }

    func testLoadPresetSummariesIsCancellable() async throws {
        let (s, u) = await makePair()
        let task = Task { await s.loadPresetSummaries() }
        while s.summaryProgress < 0.1 { await Task.yield() }
        task.cancel()
        await task.value
        let got = s.presetSummaries.compactMap { $0 }.count
        XCTAssertGreaterThan(got, 0)
        XCTAssertLessThan(got, 80)
        XCTAssertFalse(s.isLoadingSummaries)
        XCTAssertFalse(s.busy)
        // a new call reads the rest only
        await s.loadPresetSummaries()
        XCTAssertEqual(s.presetSummaries.compactMap { $0 }.count, 80)
        XCTAssertLessThan(u.receivedCommands.filter { $0 == 83 }.count, 80 + got + 3, "the ones already read are not read again")
    }

    func testSummariesAreDroppedOnReconnectAndGiveUpOnASilentUnit() async {
        let (s, u) = await makePair()
        await s.loadPresetSummaries()
        s.disconnect()
        XCTAssertTrue(s.presetSummaries.allSatisfy { $0 == nil })
        let quiet = SimulatedUnit(isBLE: false)
        let ok = await s.connect(quiet)
        XCTAssertTrue(ok)
        quiet.isSilent = true
        await s.loadPresetSummaries()
        XCTAssertEqual(s.presetSummaries.compactMap { $0 }.count, 0)
        XCTAssertEqual(quiet.receivedCommands.filter { $0 == 83 }.count, 3, "stops after three unanswered reads")
        _ = u
    }

    func testCopyUpdatesTheCachedSummary() async throws {
        let (s, _) = await makePair()
        await s.loadPresetSummaries()
        XCTAssertEqual(s.presetSummaries[44]?.isEmpty, true)
        _ = try await s.copyPreset(from: 3, to: 44, name: "Filled")
        XCTAssertEqual(s.presetSummaries[44], PresetSummary(index: 44, name: "Filled", isEmpty: false, seq: 2))
    }
}
