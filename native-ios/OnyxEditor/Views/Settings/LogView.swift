// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = model.session.uiLog
        ScrollView {
            if lines.isEmpty {
                Text("The log is empty.").foregroundStyle(Palette.mid).padding(16)
            } else {
                Text(lines.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.mid)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(Palette.bg)
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ShareLink(item: lines.joined(separator: "\n")) }
        }
    }
}
