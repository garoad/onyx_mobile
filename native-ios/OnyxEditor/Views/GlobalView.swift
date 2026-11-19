// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct GlobalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let state = model.session.state {
            ScrollView {
                Panel {
                    ForEach(Array(GlobalParam.globalTabOrder.enumerated()), id: \.element) { i, p in
                        if i > 0 { Divider().overlay(Palette.line) }
                        SpecControlRow(
                            spec: p.spec, value: p.value(in: state), caption: caption(p),
                            onEditing: { $0 ? model.session.uiBeginEditing(.global(p)) : model.session.uiEndEditing(.global(p)) },
                            onChange: { model.session.uiSetGlobal(p, $0) })
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else {
            NotConnectedView()
        }
    }

    private func caption(_ p: GlobalParam) -> String? {
        p == .usbLoopback ? String(localized: "The recording includes what the PC plays; off breaks a monitoring loop.") : nil
    }
}

#if DEBUG
#Preview("Global") { PreviewHost { GlobalView() } }
#endif
