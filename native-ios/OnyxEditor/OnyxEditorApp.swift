// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

@main
struct OnyxEditorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
