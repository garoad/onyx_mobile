// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The web editor's toast: a pill at the bottom that fades after a few seconds.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let toast = model.toast {
                Text(toast.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(toast.isError ? Color.white : Palette.onColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(toast.isError ? Palette.bad : Palette.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                    .onAppear { AccessibilityNotification.Announcement(toast.text).post() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.25), value: model.toast)
        .allowsHitTesting(false)
    }
}
