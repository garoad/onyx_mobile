// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

enum ReorderTiming {
    /// The web editor's `HOLD_MS`.
    static let hold = 1.0
}

private enum ReorderPhase: Equatable {
    case idle
    case holding(Int)
    case lifted(Int, CGSize)
}

private struct CardFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// The eight blocks in the unit's signal order. Hold a title bar for 1 s, then drag the lifted block over another one and let go: the unit follows.
struct ChainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let state: DeviceState

    @GestureState private var phase = ReorderPhase.idle
    @State private var frames: [Int: CGRect] = [:]

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)] : [GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(state.order.enumerated()), id: \.element) { pos, id in
                if let slot = Slot(rawValue: id) {
                    card(slot, position: pos)
                }
            }
        }
        .coordinateSpace(name: "chain")
        .onPreferenceChange(CardFrames.self) { frames = $0 }
        .onChange(of: phase == .idle) { _, idle in if !idle { Haptics.tick() } }
    }

    private func card(_ slot: Slot, position: Int) -> some View {
        let lifted: Bool = { if case .lifted(slot.rawValue, _) = phase { return true } else { return false } }()
        let holding: Bool = { if case .holding(slot.rawValue) = phase { return true } else { return false } }()
        let isTarget = targetPosition(for: phase).map { $0 == position && !lifted } ?? false
        let offset: CGSize = { if case .lifted(slot.rawValue, let t) = phase { return t } else { return .zero } }()
        let block = state.slots[slot.rawValue]

        return ZStack {
            VStack(spacing: 0) {
                BlockHeader(slot: slot, on: block.on, holding: holding)
                    .gesture(reorderGesture(slot))
                    .accessibilityAction(named: Text("Move earlier")) { move(slot, to: position - 1) }
                    .accessibilityAction(named: Text("Move later")) { move(slot, to: position + 1) }
                BlockBody(slot: slot, state: state)
            }
            .background(Palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(lifted ? Palette.accent : Palette.line, lineWidth: lifted ? 2 : 1))
            .overlay {
                if isTarget {
                    RoundedRectangle(cornerRadius: 10).stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 14, y: 8)
            .offset(offset)
            .scaleEffect(lifted ? 1.02 : 1)
            .zIndex(lifted ? 1 : 0)
        }
        .zIndex(lifted ? 1 : 0)
        .background(GeometryReader { geo in
            Color.clear.preference(key: CardFrames.self, value: [slot.rawValue: geo.frame(in: .named("chain"))])
        })
        .accessibilityElement(children: .contain)
    }

    private func reorderGesture(_ slot: Slot) -> some Gesture {
        LongPressGesture(minimumDuration: ReorderTiming.hold)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("chain")))
            .updating($phase) { value, state, _ in
                switch value {
                case .first: state = .holding(slot.rawValue)
                case .second(_, let drag): state = .lifted(slot.rawValue, drag?.translation ?? .zero)
                }
            }
            .onEnded { value in
                guard case .second(_, let drag) = value, let drag, let to = nearestPosition(of: slot, translation: drag.translation) else { return }
                move(slot, to: to)
            }
    }

    private func move(_ slot: Slot, to: Int) {
        guard (0...7).contains(to), state.order.firstIndex(of: slot.rawValue) != to else { return }
        Haptics.success()
        Task { await model.session.uiMoveSlot(slot, to: to) }
    }

    private func targetPosition(for phase: ReorderPhase) -> Int? {
        guard case .lifted(let id, let t) = phase, let slot = Slot(rawValue: id) else { return nil }
        return nearestPosition(of: slot, translation: t)
    }

    /// The position whose block centre is nearest to where the lifted block's centre now is (`nearest` of the web editor).
    private func nearestPosition(of slot: Slot, translation: CGSize) -> Int? {
        guard let f = frames[slot.rawValue] else { return nil }
        let p = CGPoint(x: f.midX + translation.width, y: f.midY + translation.height)
        var best: (Int, CGFloat)?
        for (pos, id) in state.order.enumerated() {
            guard let r = frames[id] else { continue }
            let d = hypot(p.x - r.midX, p.y - r.midY)
            if best == nil || d < best!.1 { best = (pos, d) }
        }
        return best?.0
    }
}
