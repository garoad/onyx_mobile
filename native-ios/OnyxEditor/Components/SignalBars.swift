// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// RSSI as one to four bars.
struct SignalBars: View {
    let rssi: Int

    private var level: Int {
        switch rssi {
        case (-55)...: return 4
        case (-67)...: return 3
        case (-78)...: return 2
        case (-90)...: return 1
        default: return 0
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= level ? Palette.accent : Palette.dim.opacity(0.5))
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(Text("Signal strength"))
        .accessibilityValue(Text("\(level) of 4"))
    }
}
