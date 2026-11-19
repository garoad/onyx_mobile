// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The web editor's small upper-case `h2`.
struct SectionTitle: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Palette.mid)
            .accessibilityAddTraits(.isHeader)
    }
}
