// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

struct PickerItem: Hashable {
    var tag: Int
    var title: String
}

/// A dropdown row: title and the current option, the options in a menu.
struct PickerRow: View {
    let title: String
    let items: [PickerItem]
    let selection: Int
    var showsTitle = true
    var tint: Color = Palette.accent
    let onChange: (Int) -> Void

    init(title: String, options: [String], selection: Int, onChange: @escaping (Int) -> Void) {
        self.init(title: title, items: options.enumerated().map { PickerItem(tag: $0.offset, title: $0.element) }, selection: selection, onChange: onChange)
    }

    init(title: String, items: [PickerItem], selection: Int, showsTitle: Bool = true, onChange: @escaping (Int) -> Void) {
        self.title = title; self.items = items; self.selection = selection; self.showsTitle = showsTitle; self.onChange = onChange
    }

    var body: some View {
        let current = items.first { $0.tag == selection }?.title ?? "?"
        VStack(alignment: .leading, spacing: 4) {
            if showsTitle { Text(title).foregroundStyle(Palette.text) }
            Menu {
                Picker(title, selection: Binding(get: { selection }, set: { Haptics.tick(); onChange($0) })) {
                    ForEach(items, id: \.tag) { Text($0.title).tag($0.tag) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(current).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Palette.mid)
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(current))
        }
    }
}

struct ToggleRow: View {
    let title: String
    var caption: String?
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { Haptics.tick(); onChange($0) }))
                .tint(Palette.accent)
                .frame(minHeight: 44)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(Palette.mid)
            }
        }
    }
}

/// Renders one `ControlSpec` (a Global or Groove setting) as a slider, a dropdown or a switch.
struct SpecControlRow: View {
    let spec: ControlSpec
    let value: Int
    var caption: String?
    var onEditing: (Bool) -> Void = { _ in }
    let onChange: (Int) -> Void

    var body: some View {
        switch spec.kind {
        case .slider(let range):
            ValueSlider(title: L(spec.title), value: value, range: range, format: { spec.text($0) }, onEditing: onEditing, onChange: onChange)
        case .picker(let options):
            PickerRow(title: L(spec.title), options: options.map(L), selection: value, onChange: onChange)
        case .toggle:
            ToggleRow(title: L(spec.title), caption: caption, isOn: value != 0) { onChange($0 ? 1 : 0) }
        }
    }
}

/// The grey rounded panel the Global / Groove / Library lists sit in (the web editor's `section`).
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
    }
}
