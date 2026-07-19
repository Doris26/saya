import Carbon.HIToolbox
import Foundation
import Testing

@testable import AIVoiceInputCore

@Suite struct HotkeyValidationTests {
    @Test func optionOnlyRejected() {
        // grill #10:macOS 15+ 禁 option-only / option+shift-only(-9868)
        #expect(throws: Hotkey.ValidationError.optionOnlyForbidden) {
            try Hotkey.validate(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
        }
        #expect(throws: Hotkey.ValidationError.optionOnlyForbidden) {
            try Hotkey.validate(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(optionKey | shiftKey))
        }
    }

    @Test func controlOrCommandAccepted() throws {
        try Hotkey.validate(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(controlKey | optionKey))
        try Hotkey.validate(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey | shiftKey))
    }

    @Test func modifierOnlyRejected() {
        #expect(throws: Hotkey.ValidationError.modifierOnly) {
            try Hotkey.validate(keyCode: nil, carbonModifiers: UInt32(controlKey))
        }
    }

    @Test func noModifierRejected() {
        #expect(throws: Hotkey.ValidationError.noModifier) {
            try Hotkey.validate(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: 0)
        }
    }
}

@Suite(.serialized) @MainActor struct SettingsStoreTests {
    private func freshStore() -> SettingsStore {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return SettingsStore(defaults: defaults)
    }

    @Test func defaultsAreSane() {
        let store = freshStore()
        #expect(store.model == "gpt-4o-transcribe")
        #expect(store.autoPunctuation == true)
        #expect(store.removeFillers == false)
        #expect(store.injectionMethod == "auto")
        #expect(store.hotkey == Hotkey.defaultToggle)
    }

    @Test func hotkeyPersistsAcrossInstances() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store1 = SettingsStore(defaults: defaults)
        let custom = Hotkey(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(controlKey | cmdKey))
        store1.hotkey = custom
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hotkey == custom)
    }

    @Test func apiKeyMaskShowsOnlyTail() {
        let store = freshStore()
        // 不写真 keychain,只测掩码逻辑对短/空串的处理
        #expect(store.apiKeyMasked == "(未设置)" || store.apiKeyMasked.hasPrefix("••••"))
    }

    @Test func triggerModeDefaultsToFnKey() {
        // owner 主交互:默认 fn 单键
        #expect(freshStore().triggerMode == .fnKey)
    }

    @Test func triggerModePersists() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store1 = SettingsStore(defaults: defaults)
        store1.triggerMode = .combo
        #expect(SettingsStore(defaults: defaults).triggerMode == .combo)
    }
}
