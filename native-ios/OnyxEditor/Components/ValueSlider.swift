// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A labelled integer slider. `onEditing` brackets a drag (the session then leaves the value alone while refreshing), `onChange` fires for every step.
struct ValueSlider: View {
    enum Layout { case inline, stacked }

    let title: String
    let value: Int
    let range: ClosedRange<Int>
    var layout: Layout = .stacked
    var format: (Int) -> String = { String($0) }
    var tint: Color = Palette.accent
    var onEditing: (Bool) -> Void = { _ in }
    let onChange: (Int) -> Void

    @ScaledMetric(relativeTo: .caption) private var labelWidth = 64
    @ScaledMetric(relativeTo: .caption) private var valueWidth = 44

    private var slider: some View {
        Slider(
            value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
            in: Double(range.lowerBound)...Double(range.upperBound), step: 1, onEditingChanged: onEditing)
            .tint(tint)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(format(value)))
    }

    var body: some View {
        switch layout {
        case .inline:
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Palette.mid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: labelWidth, alignment: .leading)
                    .accessibilityHidden(true)
                slider
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .frame(width: valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        case .stacked:
            VStack(spacing: 0) {
                HStack {
                    Text(title).foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    Text(format(value)).font(.body.monospacedDigit()).foregroundStyle(Palette.mid)
                }
                .accessibilityHidden(true)
                slider
            }
            .frame(minHeight: 44)
        }
    }
}
