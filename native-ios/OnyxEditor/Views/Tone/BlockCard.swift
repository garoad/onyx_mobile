// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// The coloured title bar of a block: name and ON/OFF. The chain view adds the reorder gesture to it.
struct BlockHeader: View {
    @Environment(AppModel.self) private var model
    let slot: Slot
    let on: Bool
    var holding = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.caption).opacity(0.55).accessibilityHidden(true)
            Text(slot.name).font(.subheadline.weight(.bold)).tracking(1)
            Spacer(minLength: 4)
            Button {
                Haptics.tick()
                model.session.uiSetSlot(slot, on: !on)
            } label: {
                Text(on ? "ON" : "OFF")
                    .font(.footnote.weight(.bold))
                    .frame(minWidth: 52, minHeight: 44)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(slot.name) block"))
            .accessibilityValue(Text(on ? "On" : "Off"))
            .accessibilityHint(Text("Switches the block on or off"))
        }
        .foregroundStyle(Palette.onColor)
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Palette.block[slot.rawValue])
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                Rectangle().fill(.white).frame(width: holding ? geo.size.width : 0, height: 3)
                    .animation(holding ? .linear(duration: ReorderTiming.hold) : nil, value: holding)
            }
            .frame(height: 3)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
    }
}

/// The model menu and the knobs of one block.
struct BlockBody: View {
    @Environment(AppModel.self) private var model
    let slot: Slot
    let state: DeviceState

    private var session: OnyxSession { model.session }
    private var block: DeviceState.SlotState { state.slots[slot.rawValue] }

    private var modelItems: [PickerItem] {
        let names: [String]
        switch slot {
        case .amp: names = session.ampNames
        case .cab: names = session.cabNames
        default: names = ChainTables.models[slot.name] ?? []
        }
        // A deleted capture / cabinet has an empty name: no entry, its number stays.
        var items = names.enumerated().filter { !$0.element.isEmpty }.map { PickerItem(tag: $0.offset, title: $0.element) }
        if slot == .cab && state.userCab { items.append(PickerItem(tag: -1, title: "USER CAB (live)")) }
        return items
    }

    var body: some View {
        let labels = ChainTables.knobLabels(slot, type: block.type)
        VStack(spacing: 4) {
            PickerRow(title: String(localized: "\(slot.name) model"), items: modelItems,
                      selection: slot == .cab && state.userCab ? -1 : block.type, showsTitle: false) { tag in
                if tag >= 0 { session.uiSetModel(slot, tag) }
            }
            ForEach(0..<min(labels.count, 6), id: \.self) { k in
                let dead = labels.isDead(k)
                ValueSlider(title: k < labels.labels.count ? labels.labels[k] : "", value: block.knobs[k], range: 0...100, layout: .inline, tint: Palette.block[slot.rawValue],
                            onEditing: { $0 ? session.uiBeginEditing(.knob(slot, k)) : session.uiEndEditing(.knob(slot, k)) },
                            onChange: { session.uiSetKnob(slot, k, $0) })
                    .opacity(dead ? 0.3 : 1)
                    .disabled(dead)
            }
        }
        .padding(10)
        .opacity(block.on ? 1 : 0.55)
    }
}
