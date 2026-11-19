// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import OnyxKit
import SwiftUI

/// Wraps a preview in an `AppModel` whose session is connected to the simulated unit.
struct PreviewHost<Content: View>: View {
    @State private var model = AppModel(scanner: SimulatedScanner(), arguments: [])
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(model)
            .task {
                guard !model.session.isConnected else { return }
                await model.session.uiConnect(SimulatedUnit(name: "Pocket AMP (Simulator)", isBLE: false))
            }
    }
}
#endif
