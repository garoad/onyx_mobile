// SPDX-License-Identifier: GPL-3.0-only
import UIKit

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}
