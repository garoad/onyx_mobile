// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The empty state of every tab.
struct NotConnectedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.session.isConnected {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading the unit…").foregroundStyle(Palette.mid)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Not connected", systemImage: "cable.connector.slash")
            } description: {
                Text("Connect to your Pocket AMP to see and edit its sound.")
            } actions: {
                Button("Connect") { model.showConnect = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}
