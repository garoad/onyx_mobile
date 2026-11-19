// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// The few JavaScript semantics the file converters depend on (number parsing and printing, `Math.round`, `toFixed`, `JSON.parse`),
/// so that the output bytes and the info strings equal the web editor's.
enum JS {
    /// `Math.round`: ties go toward +infinity.
    static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// `Math.max` / `Math.min` propagate NaN.
    static func max(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.max(a, b) }
    static func min(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.min(a, b) }

    /// `Number(x.toFixed(4))`. toFixed picks the larger candidate on an exact tie, printf rounds half to even; an exact tie needs x = odd / 32.
    static func numberFixed4(_ x: Double) -> Double {
        guard x.isFinite, abs(x) < 1e21 else { return x }
        let y = abs(x) * 32
        if y == y.rounded(), y.truncatingRemainder(dividingBy: 2) != 0 {
            return (x < 0 ? -1 : 1) * (abs(x) * 10000).rounded(.up) / 10000
        }
        return Double(String(format: "%.4f", x)) ?? x
    }

    /// `Number.prototype.toString` (shortest round-trip digits, JavaScript layout).
    static func numberString(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d == 0 { return "0" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        if d < 0 { return "-" + numberString(-d) }
        let s = "\(d)"
        var mant = Substring(s), exp = 0
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mant = s[..<e]
            exp = Int(s[s.index(after: e)...]) ?? 0
        }
        var intPart = mant, frac = Substring("")
        if let dot = mant.firstIndex(of: ".") { intPart = mant[..<dot]; frac = mant[mant.index(after: dot)...] }
        var digits = Array(intPart + frac)
        var n = intPart.count + exp
        while digits.first == "0" { digits.removeFirst(); n -= 1 }
        while digits.last == "0" { digits.removeLast() }
        let k = digits.count, ds = String(digits)
        if k <= n && n <= 21 { return ds + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 { return String(digits[..<n]) + "." + String(digits[n...]) }
        if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + ds }
        let e = n - 1, es = (e < 0 ? "-" : "+") + String(abs(e))
        return k == 1 ? ds + "e" + es : String(digits[0]) + "." + String(digits[1...]) + "e" + es
    }

    /// `Number("...")`.
    static func number(_ str: String) -> Double {
        let ws: Set<Character> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{A0}", "\u{FEFF}", "\u{2028}", "\u{2029}", "\u{1680}", "\u{202F}", "\u{205F}", "\u{3000}"]
        var u = Substring(str)
        while let c = u.first, ws.contains(c) || ("\u{2000}"..."\u{200A}").contains(c) { u.removeFirst() }
        while let c = u.last, ws.contains(c) || ("\u{2000}"..."\u{200A}").contains(c) { u.removeLast() }
        if u.isEmpty { return 0 }
        switch u {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let b = Array(u.utf8)
        if b.count > 2, b[0] == 0x30, let radix = [0x78: 16, 0x58: 16, 0x62: 2, 0x42: 2, 0x6F: 8, 0x4F: 8][Int(b[1])] {
            var v = 0.0
            for c in b[2...] {
                guard let d = Int(String(UnicodeScalar(c)), radix: radix) else { return .nan }
                v = v * Double(radix) + Double(d)
            }
            return v
        }
        // StrDecimalLiteral: [+-] (digits [. digits] | . digits) [e [+-] digits]
        var i = 0
        func digits() -> Int { let s = i; while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }; return i - s }
        if b[i] == 0x2B || b[i] == 0x2D { i += 1 }
        let a = digits()
        var f = 0
        if i < b.count, b[i] == 0x2E { i += 1; f = digits() }
        if a + f == 0 { return .nan }
        if i < b.count, b[i] == 0x65 || b[i] == 0x45 {
            i += 1
            if i < b.count, b[i] == 0x2B || b[i] == 0x2D { i += 1 }
            if digits() == 0 { return .nan }
        }
        return i == b.count ? (Double(String(u)) ?? .nan) : .nan
    }
}

/// A parsed JSON value with `JSON.parse` grammar and the JavaScript coercions (`Number(v)`, `String(v)`, truthiness) the NAM reader applies to it.
indirect enum JSONValue {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    struct ParseError: Error { var message: String }

    /// `new TextDecoder("utf-8").decode(bytes).replace(/^﻿/, "")` and `JSON.parse`.
    static func parse(utf8 bytes: [UInt8]) throws -> JSONValue {
        var text = String(decoding: bytes, as: UTF8.self)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { text = String(text.unicodeScalars.dropFirst()) }
        if text.unicodeScalars.first == "\u{FEFF}" { text = String(text.unicodeScalars.dropFirst()) }
        var p = Parser(b: Array(text.utf8))
        let v = try p.value(0)
        p.skipSpace()
        if p.i < p.b.count { throw ParseError(message: "Unexpected non-whitespace character after JSON at position \(p.i)") }
        return v
    }

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(b: [UInt8]) { self.b = b }

        func err(_ m: String = "Unexpected token") -> ParseError {
            ParseError(message: i < b.count ? "\(m) '\(String(UnicodeScalar(b[i])))' at position \(i)" : "Unexpected end of JSON input")
        }
        mutating func skipSpace() { while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } }

        mutating func value(_ depth: Int) throws -> JSONValue {
            if depth > 512 { throw ParseError(message: "nesting too deep") }
            skipSpace()
            guard i < b.count else { throw err() }
            switch b[i] {
            case 0x7B:
                i += 1; skipSpace()
                var o: [String: JSONValue] = [:]
                if i < b.count, b[i] == 0x7D { i += 1; return .object(o) }
                while true {
                    skipSpace()
                    guard i < b.count, b[i] == 0x22 else { throw err() }
                    let k = try string()
                    skipSpace()
                    guard i < b.count, b[i] == 0x3A else { throw err() }
                    i += 1
                    o[k] = try value(depth + 1)
                    skipSpace()
                    guard i < b.count else { throw err() }
                    if b[i] == 0x2C { i += 1; continue }
                    if b[i] == 0x7D { i += 1; return .object(o) }
                    throw err()
                }
            case 0x5B:
                i += 1; skipSpace()
                var a: [JSONValue] = []
                if i < b.count, b[i] == 0x5D { i += 1; return .array(a) }
                while true {
                    a.append(try value(depth + 1))
                    skipSpace()
                    guard i < b.count else { throw err() }
                    if b[i] == 0x2C { i += 1; continue }
                    if b[i] == 0x5D { i += 1; return .array(a) }
                    throw err()
                }
            case 0x22: return .string(try string())
            case 0x74: try literal("true"); return .bool(true)
            case 0x66: try literal("false"); return .bool(false)
            case 0x6E: try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ s: String) throws {
            for c in s.utf8 { guard i < b.count, b[i] == c else { throw err() }; i += 1 }
        }

        mutating func number() throws -> Double {
            let s = i
            if i < b.count, b[i] == 0x2D { i += 1 }
            guard i < b.count, b[i] >= 0x30, b[i] <= 0x39 else { throw err() }
            if b[i] == 0x30 { i += 1 } else { while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 } }
            if i < b.count, b[i] == 0x2E {
                i += 1
                guard i < b.count, b[i] >= 0x30, b[i] <= 0x39 else { throw err() }
                while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
            }
            if i < b.count, b[i] == 0x65 || b[i] == 0x45 {
                i += 1
                if i < b.count, b[i] == 0x2B || b[i] == 0x2D { i += 1 }
                guard i < b.count, b[i] >= 0x30, b[i] <= 0x39 else { throw err() }
                while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
            }
            return Double(String(decoding: b[s..<i], as: UTF8.self)) ?? .nan
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= b.count else { throw err() }
            var v: UInt32 = 0
            for _ in 0..<4 {
                guard let d = Int(String(UnicodeScalar(b[i])), radix: 16) else { throw err() }
                v = v * 16 + UInt32(d); i += 1
            }
            return v
        }

        mutating func string() throws -> String {
            i += 1
            var out: [UInt8] = []
            while true {
                guard i < b.count else { throw err() }
                let c = b[i]
                if c == 0x22 { i += 1; return String(decoding: out, as: UTF8.self) }
                if c < 0x20 { throw err() }
                if c != 0x5C { out.append(c); i += 1; continue }
                i += 1
                guard i < b.count else { throw err() }
                let e = b[i]; i += 1
                switch e {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    var u = try hex4()
                    if (0xD800..<0xDC00).contains(u), i + 6 <= b.count, b[i] == 0x5C, b[i + 1] == 0x75 {
                        let save = i
                        i += 2
                        let lo = try hex4()
                        if (0xDC00..<0xE000).contains(lo) { u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00) } else { i = save }
                    }
                    out += Array(String(Unicode.Scalar(u) ?? "\u{FFFD}").utf8)
                default: i -= 1; throw err()
                }
            }
        }
    }

    // MARK: JavaScript views

    /// `v.key` on an object; nil (undefined) on anything else or a missing key.
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var isObject: Bool { if case .object = self { return true } else { return false } }

    /// JavaScript truthiness.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let d): return d != 0 && !d.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// `String(v)`.
    var jsString: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return JS.numberString(d)
        case .string(let s): return s
        case .array(let a): return a.map { if case .null = $0 { return "" } else { return $0.jsString } }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// `Number(v)`.
    var jsNumber: Double {
        switch self {
        case .null: return 0
        case .bool(let b): return b ? 1 : 0
        case .number(let d): return d
        case .string(let s): return JS.number(s)
        case .array: return JS.number(jsString)
        case .object: return .nan
        }
    }
}

extension Optional where Wrapped == JSONValue {
    var truthy: Bool { self?.truthy ?? false }
}
