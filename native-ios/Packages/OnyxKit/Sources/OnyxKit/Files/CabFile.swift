// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The cabinet impulse response the unit takes: raw Q18 taps (int32 little endian, 16 to 1024) at 44.1 kHz. A WAV is resampled, trimmed and
/// cut to 1024 taps (`checkCab`, `parseWav`, `resample`, `wavToCab` of the web editor).
public enum CabFile {
    public struct Result: Equatable, Sendable {
        /// What to upload (nil on error).
        public var bytes: [UInt8]?
        public var taps: Int?
        /// Peak as a fraction of full scale (Q18 = 262144).
        public var peak: Double?
        /// What the status line says about the conversion (WAV only).
        public var how: String?
        public var error: String?
    }

    public static let rate = 44100
    public static let maxTaps = 1024

    /// `checkCab(f)`.
    public static func convert(_ f: [UInt8]) -> Result {
        if f.count > 12, f[0] == 0x52, f[1] == 0x49, f[2] == 0x46, f[3] == 0x46 { return fromWav(f) }
        let n = f.count
        if n % 4 != 0 || n < 64 || n > 4096 { return Result(error: "a cabinet is 16..1024 int32 taps (64..4096 bytes); this file is \(n) bytes") }
        var peak: Int64 = 0
        for i in stride(from: 0, to: n, by: 4) {
            let v = Int32(bitPattern: UInt32(f[i]) | UInt32(f[i + 1]) << 8 | UInt32(f[i + 2]) << 16 | UInt32(f[i + 3]) << 24)
            peak = max(peak, abs(Int64(v)))
        }
        if peak == 0 { return Result(error: "the impulse is all zeros") }
        return Result(bytes: f, taps: n / 4, peak: Double(peak) / 262144)
    }

    // MARK: WAV

    struct Wav {
        var x: [Double]
        var rate: Int
        var channels: Int
        var error: String?
    }

    /// `parseWav`: the first channel as Float64 (16/24/32-bit PCM, 32/64-bit float, WAVE_FORMAT_EXTENSIBLE, chunks padded to even length).
    static func parseWav(_ f: [UInt8]) -> Wav {
        func fail(_ s: String) -> Wav { Wav(x: [], rate: 0, channels: 0, error: s) }
        // a DataView read past the end throws in JavaScript: it is an error here, checked where the editor would have thrown
        var cut = false
        func u16(_ o: Int) -> Int { guard o + 2 <= f.count else { cut = true; return 0 }; return Int(f[o]) | Int(f[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { guard o + 4 <= f.count else { cut = true; return 0 }; return Int(f[o]) | Int(f[o + 1]) << 8 | Int(f[o + 2]) << 16 | Int(f[o + 3]) << 24 }
        let truncated = "the WAV is cut short"
        func tag(_ o: Int) -> String { String(String.UnicodeScalarView(f[o..<(o + 4)].map { Unicode.Scalar($0) })) }
        if f.count < 44 || tag(0) != "RIFF" || tag(8) != "WAVE" { return fail("not a WAV file") }
        var fmt: (code: Int, ch: Int, rate: Int, bits: Int)?, data: (o: Int, n: Int)?
        var o = 12
        while o + 8 <= f.count {
            let id = tag(o), n = u32(o + 4)
            if id == "fmt " { fmt = (u16(o + 8), u16(o + 10), u32(o + 12), u16(o + 22)); if cut { return fail(truncated) } }
            if id == "data" { data = (o + 8, min(n, f.count - o - 8)); break }
            o += 8 + n + (n & 1)
        }
        guard var fmt, let data else { return fail("no fmt or data chunk in the WAV") }
        if fmt.code == 0xFFFE { fmt.code = u16(40); if cut { return fail(truncated) } }
        let bytes = fmt.bits >> 3
        let frames = bytes * fmt.ch == 0 ? 0 : data.n / (bytes * fmt.ch)
        if fmt.code != 1 && fmt.code != 3 { return fail("WAV format \(fmt.code) is not PCM or float") }
        if ![16, 24, 32, 64].contains(fmt.bits) || (fmt.code == 1 && fmt.bits == 64) { return fail("\(fmt.bits)-bit samples are not supported") }
        var x = [Double](repeating: 0, count: frames)
        for i in 0..<frames {
            let p = data.o + i * bytes * fmt.ch
            if fmt.code == 3 {
                if fmt.bits == 32 { x[i] = Double(Float(bitPattern: UInt32(truncatingIfNeeded: u32(p)))) }
                else { x[i] = Double(bitPattern: UInt64(u32(p)) | UInt64(u32(p + 4)) << 32) }
                if cut { return fail(truncated) }
            } else if fmt.bits == 16 {
                x[i] = Double(Int16(bitPattern: UInt16(u16(p)))) / 32768
            } else if fmt.bits == 24 {
                let v = Int(f[p]) | Int(f[p + 1]) << 8 | Int(Int8(bitPattern: f[p + 2])) << 16
                x[i] = Double(v) / 8388608
            } else {
                x[i] = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: u32(p)))) / 2147483648
            }
        }
        return Wav(x: x, rate: fmt.rate, channels: fmt.ch, error: nil)
    }

    /// `resample`: Lanczos 3, Float64 throughout (the same operations in the same order as the editor, so the output is bit-identical).
    static func resample(_ x: [Double], from: Int, to: Int) -> [Double] {
        if from == to { return x }
        let n = Int((Double(x.count) * Double(to) / Double(from)).rounded(.down))
        var y = [Double](repeating: 0, count: max(0, n))
        let r = Double(from) / Double(to), a = 3.0, fc = Swift.min(1.0, Double(to) / Double(from))
        func sinc(_ t: Double) -> Double { t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t) }
        for i in 0..<y.count {
            let c = Double(i) * r
            var acc = 0.0
            var j = Int((c - a / fc).rounded(.up))
            let last = Int((c + a / fc).rounded(.down))
            while j <= last {
                if j >= 0 && j < x.count { let t = (c - Double(j)) * fc; acc += x[j] * fc * sinc(t) * sinc(t / a) }
                j += 1
            }
            y[i] = acc
        }
        return y
    }

    /// `wavToCab`.
    static func fromWav(_ f: [UInt8]) -> Result {
        let w = parseWav(f)
        if let e = w.error { return Result(error: e) }
        var y = resample(w.x, from: w.rate, to: rate)
        var peak = 0.0
        for v in y { peak = JS.max(peak, abs(v)) }
        if peak == 0 || peak.isNaN { return Result(error: "the impulse is silent") }
        var first = 0
        while first < y.count && abs(y[first]) < 0.05 * peak { first += 1 }       // the lead-in before the response starts
        first = Swift.max(0, first - 4)
        y = Array(y[Swift.min(first, y.count)..<Swift.min(first + maxTaps, y.count)])
        if y.count < 16 { return Result(error: "the impulse is shorter than 16 samples") }
        let fade = Swift.min(128, y.count >> 2)
        for i in 0..<fade { y[y.count - 1 - i] *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fade)) }      // a half-Hann tail: no click from the cut
        let k = 0.9 * 262144 / peak
        var out = [UInt8](repeating: 0, count: y.count * 4)
        for (i, v) in y.enumerated() {
            let q = JS.round(v * k)
            let c = JS.max(-2147483648, JS.min(2147483647, q))
            let u = UInt32(bitPattern: c.isNaN ? 0 : Int32(c))
            for b in 0..<4 { out[i * 4 + b] = UInt8(truncatingIfNeeded: u >> UInt32(8 * b)) }
        }
        var how = "WAV \(w.rate) Hz, \(w.x.count) samples"
        if w.rate != rate { how += " resampled to 44.1 kHz" }
        if first != 0 { how += ", \(first) lead-in samples removed" }
        if w.x.count - first > maxTaps { how += ", cut to 1024 taps with a soft tail" }
        return Result(bytes: out, taps: y.count, peak: 0.9, how: how)
    }
}
