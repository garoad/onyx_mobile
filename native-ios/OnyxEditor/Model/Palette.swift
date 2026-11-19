// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit

/// The web editor's CSS variables (dark default, light under prefers-color-scheme: light) and its block colours.
enum Palette {
    static let bg = dynamic(dark: 0x0c0c0e, light: 0xf3f3f5)
    static let surface = dynamic(dark: 0x18181c, light: 0xe6e6ea)
    static let raised = dynamic(dark: 0x26262c, light: 0xd6d6dc)
    static let line = dynamic(dark: 0x2c2c33, light: 0xc6c6ce)
    static let text = dynamic(dark: 0xd4d4da, light: 0x1d1d22)
    /// Secondary text; `dim` is only for disabled or decorative things (too faint to read).
    static let mid = dynamic(dark: 0x8e8e99, light: 0x5d5d68)
    static let dim = dynamic(dark: 0x5b5b66, light: 0x8c8c97)
    static let accent = dynamic(dark: 0xff7a1a, light: 0xd85f00)
    static let ok = dynamic(dark: 0x35c46a, light: 0x1e8f4a)
    static let bad = dynamic(dark: 0xff4d4d, light: 0xc62828)
    /// Text on an accent or block-coloured background (the CSS uses #111).
    static let onColor = Color(hex: 0x111111)

    /// `COLORS` of the web editor, by slot id.
    static let block: [Color] = [0x8c8c99, 0xe0a030, 0xff7a1a, 0xb070e0, 0x5fb0e0, 0x40c0a0, 0xe05a8a, 0x6a8cff].map { Color(hex: $0) }

    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}
