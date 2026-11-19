// SPDX-License-Identifier: GPL-3.0-only
// Part of Onyx Editor for iOS, a Swift port of the Onyx Web Editor (Pocket-Onyx, (C) 2026 The Onyx Authors, @28spawn).

import Foundation

/// What the Settings > MIDI pedal help screen states about the link (reference/MIDI-MAP-CUSTOM.md sections 1 / 1b, usb_ble.c).
public enum MIDIConnectionFacts {
    /// The unit reacts on every channel: only `status & 0xF0` is looked at (usb_ble.c `handle_midi_pedal_event`).
    public static let omniChannel = true
    public static let channelNote = "The unit ignores the MIDI channel: a message on any of the 16 channels is accepted. Leave the pedal on its default channel."
    public static let bleServiceUUID = BLEMIDI.serviceUUID
    public static let bleCharacteristicUUID = BLEMIDI.characteristicUUID
    /// The pedal programs these three message types; SysEx is only used by the editor.
    public static let messageTypes = ["Program Change (0xC0)", "Control Change (0xB0)", "NRPN (a run of Control Changes 99, 98, 6 and 38)"]
    public static let sysExNote = "SysEx is NOT needed for mapping: a pedal only has to send Program Change and Control Change."

    public struct ValueRule: Hashable, Sendable {
        public let messages: String
        public let rule: String
    }

    /// The value rules, as a table.
    public static let valueRules: [ValueRule] = [
        .init(messages: "Program Change 0..79", rule: "Selects P01..P80. 80 and above are ignored."),
        .init(messages: "Buttons: CC 20..27 (toggle), 64..67, 80, 81, 88", rule: "Value >= 64 acts, below 64 is ignored. Send 127 on press."),
        .init(messages: "Sets: CC 28..35, 85, 86, 87", rule: "Value >= 64 on, below 64 off (87: STOMP / PRESET)."),
        .init(messages: "Continuous: CC 7, CC 102..118", rule: "Every value acts, 0..127 maps to 0..100 %."),
        .init(messages: "CC 88 (save)", rule: "Needs a value >= 64, otherwise nothing is saved."),
        .init(messages: "NRPN modules 0..7", rule: "CC 99 = module, CC 98 = parameter, CC 6 = high 7 bits, optional CC 38 = low 7 bits: 14 bit -> 0..100 %. CC 6 alone: 0..127 -> 0..100 %."),
        .init(messages: "NRPN modules 8..10", rule: "The value is a raw number D, not a percentage: CC 6 = D alone when D < 128, else CC 6 = D >> 7 and CC 38 = D & 127 (BPM)."),
        .init(messages: "CC 101 or CC 100 = 127", rule: "RPN null: clears the NRPN selection; a data entry without a selection is ignored."),
        .init(messages: "Everything else", rule: "Other CC numbers (including 119, reserved) are ignored."),
    ]
}

public struct GuideSection: Identifiable, Hashable, Sendable {
    public let title: String
    public let body: String
    public var id: String { title }
}

/// The static texts of the help screen (English; the app localises them).
public enum MIDIPedalGuide {
    public static let title = "MIDI pedal mapping"

    public static let intro = "Program the buttons and pedals of your foot controller with the messages below and the Pocket AMP follows them. The editor app does not need to be connected."

    public static let sections: [GuideSection] = [
        .init(title: "Connecting the pedal",
              body: "The unit takes MIDI over USB and over Bluetooth LE (BLE-MIDI 1.0). Both paths use the same decoder, so every command works on either. "
                  + "BLE-MIDI service \(MIDIConnectionFacts.bleServiceUUID), characteristic \(MIDIConnectionFacts.bleCharacteristicUUID) (notify + write without response)."),
        .init(title: "MIDI channel",
              body: MIDIConnectionFacts.channelNote),
        .init(title: "What the pedal must send",
              body: "Program Change, Control Change and NRPN (which is a sequence of Control Changes). " + MIDIConnectionFacts.sysExNote),
        .init(title: "Value rules",
              body: MIDIConnectionFacts.valueRules.map { "\($0.messages): \($0.rule)" }.joined(separator: "\n")),
        .init(title: "Reading the list",
              body: "Each entry shows the message, its bytes in hex (for example B0 15 7F) and in decimal, and what the unit does. Controller editors usually ask for the "
                  + "message type, the number and the value; use the hex or decimal example to check what you entered. Tap an entry to copy it, or use Share to export the whole list as text."),
        .init(title: "Not available",
              body: "NRPN PRESET 1 (input trim) and 2 (gate threshold) are stored by the unit but do nothing yet. CC 119 is reserved. Other CC numbers are ignored."),
    ]

    public static let mappingTips: [GuideSection] = [
        .init(title: "Toggle an effect",
              body: "To switch the amp block with a footswitch, send CC 21 with value 127 on press (toggle). The order is FX 20, AMP 21, MOD 22, DLY 23, REV 24, CAB 25, DRIVE 26, EQ 27."),
        .init(title: "Latching or momentary switch",
              body: "A toggle can drift out of step when the pedal and the unit disagree. If the pedal has a latching switch or an LED that shows on/off, use the SET commands CC 28..35 "
                  + "(value 127 = on, 0 = off, order FX AMP MOD DLY REV CAB DRIVE EQ) so the LED always matches the unit. A momentary switch works best with the toggle commands."),
        .init(title: "Expression pedal",
              body: "Send CC 7 for the preset volume, or one of CC 102..118 for a single knob (for example CC 102 AMP gain, CC 109 delay time). The full 0..127 travel maps to 0..100 %. "
                  + "Set the pedal's minimum to 0 and maximum to 127."),
        .init(title: "Preset up / down",
              body: "Send CC 80 for the next preset and CC 81 for the previous one (value 127, they wrap around). Or send a Program Change 0..79 per button to jump to a preset directly."),
        .init(title: "Channel",
              body: "Any channel works. If the pedal asks, leave it on channel 1."),
        .init(title: "Saving",
              body: "A change made over MIDI is live only. Send CC 88 (value 127) to store the current sound in the current preset."),
        .init(title: "Stomp mode",
              body: "CC 87 value 127 switches the unit to STOMP mode, 0 back to PRESET mode. In STOMP mode the four keys can be given blocks with NRPN 10/3..6."),
    ]
}
