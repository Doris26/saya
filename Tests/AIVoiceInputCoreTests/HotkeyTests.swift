import AppKit
import Carbon.HIToolbox
import Testing

@testable import AIVoiceInputCore

@Suite struct HotkeyTests {
    @Test func carbonModifierConversion() {
        // 实测锚点(FINDINGS §3.6):[.control,.option] → 0x1800
        let carbon = Hotkey.carbonModifiers(from: [.control, .option])
        #expect(carbon == UInt32(controlKey | optionKey))
        #expect(carbon == 0x1800)
        #expect(Hotkey.carbonModifiers(from: [.command]) == UInt32(cmdKey))
        #expect(Hotkey.carbonModifiers(from: [.command, .shift]) == UInt32(cmdKey | shiftKey))
        #expect(Hotkey.carbonModifiers(from: []) == 0)
    }

    @Test func defaultToggleIsCtrlOptV() {
        // grill #10:默认热键唯一 ⌃⌥V(macOS 15+ 禁 option-only 组合)
        let hotkey = Hotkey.defaultToggle
        #expect(hotkey.keyCode == UInt32(kVK_ANSI_V))
        #expect(hotkey.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(hotkey.displayString == "⌃⌥V")
    }
}
