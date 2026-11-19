// SPDX-License-Identifier: GPL-3.0-only
import OnyxKit
import SwiftUI

/// Read-only: the stored captures and cabinets. The web editor stores new ones over USB only (7.5 KB per capture is too much for Bluetooth).
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    private var session: OnyxSession { model.session }

    var body: some View {
        if session.isConnected, let state = session.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Panel {
                        Label("Amp captures and cabinets are stored over USB only: Bluetooth is too slow for them. Use the web editor with a USB cable to add, rename or delete them.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.mid)
                    }
                    list(title: "Captures", rows: rows(session.ampNames, first: session.firstAmp), count: state.namCount, max: 10, free: state.namFree)
                    list(title: "Cabinets", rows: rows(session.cabNames, first: session.firstCab), count: state.cabCount, max: 15, free: state.cabFree)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else {
            NotConnectedView()
        }
    }

    private struct Row: Identifiable {
        var number: Int
        var name: String
        var id: Int { number }
    }

    /// `storedRows` of the web editor: the entries from `first` on that have a name.
    private func rows(_ names: [String], first: Int) -> [Row] {
        guard first < names.count else { return [] }
        return (first..<names.count).compactMap { names[$0].isEmpty ? nil : Row(number: $0 - first + 1, name: names[$0]) }
    }

    private func list(title: LocalizedStringKey, rows: [Row], count: Int, max: Int, free: Int) -> some View {
        Panel {
            HStack {
                SectionTitle(title)
                Spacer()
                Text("\(count) of \(max) stored, \(free) free").font(.footnote).foregroundStyle(Palette.mid)
            }
            if rows.isEmpty {
                Text("Nothing stored").foregroundStyle(Palette.mid).frame(minHeight: 44, alignment: .leading)
            }
            ForEach(rows) { r in
                Divider().overlay(Palette.line)
                HStack(spacing: 12) {
                    Text("\(r.number)").font(.body.monospacedDigit()).foregroundStyle(Palette.mid).frame(width: 32, alignment: .leading)
                    Text(r.name)
                    Spacer()
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Library") { PreviewHost { LibraryView() } }
#endif
