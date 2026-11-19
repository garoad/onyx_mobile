// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

/// Byte parity of the file converters with the editor's JavaScript (Tools/golden/gen_files.cjs).
final class FilesGoldenTests: XCTestCase {
    struct Fix: Decodable {
        var nam: [Nam]
        var cab: [Cab]
        var abkxBanks: [String: String]
        var abkx: [Abkx]
        var docs: [Doc]
        var unit: [Unit]
        var numbers: Numbers
    }
    struct Out: Decodable {
        var threw: String?
        var error: String?
        var how: String?
        var name: String?
        var makeup_db: Double?
        var cab: Bool?
        var taps: Int?
        var peak: Double?
        var bytesHex: String?
        var bytesLen: Int?
        var bytesSha: String?
        var bytesHead: String?
    }
    struct Nam: Decodable { var id: String; var filename: String; var input: String?; var text: String?; var out: Out }
    struct Cab: Decodable { var id: String; var input: String; var out: Out }
    struct Opt: Decodable { var preserveChain: Bool?; var copyAmpLevel: Bool?; var namePrefix: String?; var genre: Double? }
    struct AbkxOut: Decodable { var error: String?; var docSha: String?; var docLen: Int?; var recordsSha: String?; var presets: Int?; var empty: Int?; var docText: String?; var records: [String?]? }
    struct Abkx: Decodable { var id: String; var bank: String?; var input: String?; var opt: Opt; var out: AbkxOut }
    struct DocOut: Decodable { var kind: String; var records: [String?]?; var recordsSha: String?; var count: Int?; var empty: Int? }
    struct Doc: Decodable { var id: String; var text: String; var out: DocOut }
    struct Unit: Decodable { var id: String; var records: [String?]; var docSha: String; var docLen: Int; var docText: String? }
    struct Numbers: Decodable {
        struct S: Decodable { var n: Double; var s: String }
        struct T: Decodable { var s: String; var n: String }
        struct F: Decodable { var x: Double; var r: Double }
        var toString: [S]; var toNumber: [T]; var fixed4: [F]; var round: [F]
    }

    static let fix: Fix = try! Fixtures.load("files")

    // MARK: SHA-256 (the fixtures hash their big outputs)

    static func sha256(_ message: [UInt8]) -> String {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var m = message
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        let bits = UInt64(message.count) * 8
        for i in (0..<8).reversed() { m.append(UInt8(truncatingIfNeeded: bits >> UInt64(8 * i))) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: m.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = UInt32(m[chunk + 4 * i]) << 24 | UInt32(m[chunk + 4 * i + 1]) << 16 | UInt32(m[chunk + 4 * i + 2]) << 8 | UInt32(m[chunk + 4 * i + 3]) }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3), s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let t1 = hh &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
                let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    func testSha256Helper() {
        XCTAssertEqual(Self.sha256([]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(Self.sha256(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Self.sha256(Array(String(repeating: "a", count: 1000).utf8)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    /// A stored output: the bytes in full, or length + SHA-256 + the first 64 bytes.
    func checkBytes(_ got: [UInt8]?, _ want: Out, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        if let h = want.bytesHex { XCTAssertEqual(got.map(hex), h, id, file: file, line: line); return }
        if let n = want.bytesLen, let sha = want.bytesSha {
            guard let got else { return XCTFail("\(id): no bytes", file: file, line: line) }
            XCTAssertEqual(got.count, n, id, file: file, line: line)
            XCTAssertEqual(hex(Array(got.prefix(64))), want.bytesHead, id, file: file, line: line)
            XCTAssertEqual(Self.sha256(got), sha, id, file: file, line: line)
            return
        }
        XCTAssertNil(got, id, file: file, line: line)
    }

    // MARK: JavaScript helpers

    func testNumberToString() {
        for c in Self.fix.numbers.toString { XCTAssertEqual(JS.numberString(c.n), c.s, "\(c.n)") }
    }

    func testNumberFromString() {
        for c in Self.fix.numbers.toNumber {
            let got = JS.number(c.s)
            XCTAssertEqual(got.isNaN ? "NaN" : JS.numberString(got), c.n, "\"\(c.s)\"")
        }
    }

    func testFixed4AndRound() {
        for c in Self.fix.numbers.fixed4 { XCTAssertEqual(JS.numberFixed4(c.x), c.r, "\(c.x)") }
        for c in Self.fix.numbers.round { XCTAssertEqual(JS.round(c.x), c.r, "\(c.x)") }
    }

    // MARK: NAM

    func testNAM() {
        var checked = 0
        for c in Self.fix.nam {
            let input: [UInt8]
            if let h = c.input { input = Fixtures.bytes(h) } else {
                let w0 = (0..<1870).map { Self.cheap($0) }, w1 = (0..<1871).map { Self.cheap($0) }
                input = Array(c.text!.replacingOccurrences(of: "$W1870", with: Self.jsonList(w0)).replacingOccurrences(of: "$W1871", with: Self.jsonList(w1)).utf8)
            }
            let r = NAMFile.convert(input, filename: c.filename)
            if c.out.threw != nil { XCTAssertNotNil(r.error, c.id); checked += 1; continue }
            XCTAssertEqual(Self.stripEngineText(r.error), Self.stripEngineText(c.out.error), c.id)
            XCTAssertEqual(r.how, c.out.how, c.id)
            XCTAssertEqual(r.name, c.out.name, c.id)
            XCTAssertEqual(r.makeupDb, c.out.makeup_db, c.id)
            XCTAssertEqual(r.cabinetBakedIn, c.out.cab, c.id)
            checkBytes(r.bytes, c.out, c.id)
            checked += 1
        }
        XCTAssertEqual(checked, Self.fix.nam.count)
        XCTAssertGreaterThan(checked, 150)
    }

    /// The words of a JSON syntax error are the JavaScript engine's own and differ between engines; only the editor's sentence around them is compared.
    static func stripEngineText(_ e: String?) -> String? {
        guard let e, e.hasPrefix("this file is not valid JSON (") else { return e }
        return "this file is not valid JSON"
    }

    /// The generator's "cheap" weights, printed the way JSON.stringify prints them.
    static func cheap(_ i: Int) -> Double { Double(i % 7 - 3) / 4 }
    static func jsonList(_ a: [Double]) -> String { "[" + a.map { JS.numberString($0) }.joined(separator: ",") + "]" }

    // MARK: cabinet

    func testCabinet() {
        for c in Self.fix.cab {
            let r = CabFile.convert(Fixtures.bytes(c.input))
            if c.out.threw != nil { XCTAssertNotNil(r.error, c.id); continue }
            XCTAssertEqual(r.error, c.out.error, c.id)
            XCTAssertEqual(r.taps, c.out.taps, c.id)
            XCTAssertEqual(r.peak, c.out.peak, c.id)
            XCTAssertEqual(r.how, c.out.how, c.id)
            checkBytes(r.bytes, c.out, c.id)
        }
        XCTAssertGreaterThan(Self.fix.cab.count, 65)
    }

    // MARK: preset files

    func options(_ o: Opt) -> PresetBankFile.AbkxOptions {
        var x = PresetBankFile.AbkxOptions()
        if let v = o.preserveChain { x.preserveChain = v }
        if let v = o.copyAmpLevel { x.copyAmpLevel = v }
        if let v = o.namePrefix { x.namePrefix = v }
        // the editor does `genre | 0`
        if let v = o.genre { x.genre = Int(v.rounded(.towardZero)) }
        return x
    }

    func testAbkx() throws {
        for c in Self.fix.abkx {
            let bank = Fixtures.bytes(c.bank.map { Self.fix.abkxBanks[$0]! } ?? c.input!)
            let doc: PresetBankDocument
            do { doc = try PresetBankFile.abkx(bank, options: options(c.opt)) } catch {
                XCTAssertEqual((error as? PresetBankFile.FormatError)?.message, c.out.error, c.id)
                continue
            }
            XCTAssertNil(c.out.error, c.id)
            let text = doc.jsonData()
            XCTAssertEqual(Self.sha256(Array(text)), c.out.docSha, c.id)
            XCTAssertEqual(String(decoding: text, as: UTF8.self).utf16.count, c.out.docLen, c.id)
            if let t = c.out.docText { XCTAssertEqual(String(decoding: text, as: UTF8.self), t, c.id) }
            let recs = try PresetBankFile.recordBytes(doc)
            XCTAssertEqual(Self.sha256(Self.digestInput(recs)), c.out.recordsSha, c.id)
            if let want = c.out.records { XCTAssertEqual(recs.map { $0.map(hex) }, want, c.id) }
            XCTAssertEqual(doc.presets.filter { if case .preset(let e) = $0 { return !e.empty } else { return false } }.count, c.out.presets, c.id)
            // the document survives its own file format
            XCTAssertEqual(try PresetBankFile.parse(data: text), doc, c.id)
        }
        XCTAssertGreaterThan(Self.fix.abkx.count, 35)
    }

    static func digestInput(_ recs: [[UInt8]?]) -> [UInt8] { recs.flatMap { r in r.map { [1] + $0 } ?? [0] } }

    func testDocumentsReadLikeTheEditor() throws {
        for c in Self.fix.docs {
            let data = Data(c.text.utf8)
            var recs: [[UInt8]?]?, kind = "ok"
            do { recs = try PresetBankFile.recordBytes(try PresetBankFile.parse(data: data)) } catch let e as PresetBankFile.FormatError {
                kind = e.message == "not a JSON file" ? "notjson" : e.message == "not a pocket-amp-presets file" ? "notdoc" : e.message.hasPrefix("slot_order/slot_type") ? "length" : "other"
            }
            // a JavaScript TypeError (null element, missing params) is any error here
            if c.out.kind == "other" { XCTAssertNotEqual(kind, "ok", c.id); continue }
            XCTAssertEqual(kind, c.out.kind, c.id)
            guard let recs else { continue }
            if let want = c.out.records { XCTAssertEqual(recs.map { $0.map(hex) }, want, c.id) }
            if let sha = c.out.recordsSha { XCTAssertEqual(Self.sha256(Self.digestInput(recs)), sha, c.id) }
        }
        XCTAssertGreaterThan(Self.fix.docs.count, 30)
    }

    func testDocumentFromUnitRecords() throws {
        for c in Self.fix.unit {
            let raw = c.records.map { $0.map { Fixtures.bytes($0) } }
            let recs = raw.map { $0.flatMap { PresetRecord(record: $0) } }
            XCTAssertEqual(recs.map { $0 == nil }, raw.map { $0 == nil }, c.id)
            let doc = PresetBankFile.document(from: recs)
            let text = doc.jsonData()
            XCTAssertEqual(Self.sha256(Array(text)), c.docSha, c.id)
            XCTAssertEqual(String(decoding: text, as: UTF8.self).utf16.count, c.docLen, c.id)
            if let t = c.docText { XCTAssertEqual(String(decoding: text, as: UTF8.self), t, c.id) }
            // JSON -> document -> records returns the records the unit sent
            let back = try PresetBankFile.parse(data: text)
            XCTAssertEqual(back, doc, c.id)
            let bytes = try PresetBankFile.recordBytes(back)
            XCTAssertEqual(bytes.prefix(raw.count).map { $0.map(hex) }, raw.map { $0.map(hex) }, c.id)
            XCTAssertEqual(try PresetBankFile.records(back).prefix(raw.count).map { $0 }, recs, c.id)
            // the Entry built straight from the record bytes is the one built from the PresetRecord
            for (i, r) in raw.enumerated() { if let r { XCTAssertEqual(PresetBankDocument.Entry(index: i, record: r), PresetBankDocument.Entry(index: i, record: recs[i]!), c.id) } }
        }
    }

    func testDocumentKeysAreTheEditorsKeys() throws {
        var r = try XCTUnwrap(PresetRecord(record: Fixtures.bytes(Self.fix.unit[0].records[0]!)))
        r.name = "Key check"
        let json = try JSONSerialization.jsonObject(with: PresetBankFile.document(from: [r, nil]).jsonData()) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["format", "version", "record_size", "note", "presets"])
        let items = json["presets"] as! [[String: Any]]
        XCTAssertEqual(Set(items[0].keys), ["slot", "name", "empty", "seq", "bpm", "genre", "custom_cab_idx", "custom_cab_blend", "input_trim_db", "gate_threshold_pct",
                                            "slot_enable_mask", "slot_order", "amp_model", "cab_model", "preset_vol", "flags", "slot_type", "stomp_map", "params", "params_pct"])
        XCTAssertEqual(Set(items[1].keys), ["slot", "unreadable"])
        XCTAssertEqual(items[1]["slot"] as? Int, 2)
    }
}
