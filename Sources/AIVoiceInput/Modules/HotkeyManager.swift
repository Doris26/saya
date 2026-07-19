import AppKit
import Carbon.HIToolbox

/// 全局快捷键定义。modifiers 存 Carbon mask(cmdKey=0x0100 等);
/// 与 NSEvent.ModifierFlags 位布局不同,必须按位翻译,不能 raw cast(实测,FINDINGS §3.6)。
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// 默认 ⌃⌥V:避开 Spotlight 的 ⌘Space(PLAN §2.1)
    static let defaultToggle = Hotkey(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    var displayString: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName
    }

    private var keyName: String {
        switch Int(keyCode) {
        case kVK_ANSI_V: "V"
        case kVK_ANSI_R: "R"
        case kVK_Space: "Space"
        default: "#\(keyCode)"
        }
    }
}

/// Carbon RegisterEventHotKey 封装。收全局热键不需要任何 TCC 权限(实测,FINDINGS §1-2);
/// 前提:真 .app bundle + 活的 NSApplication runloop(LSUIElement + .accessory)。
@MainActor
final class HotkeyManager {
    enum HotkeyError: LocalizedError {
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let status): "RegisterEventHotKey err=\(status)"
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?

    private static let signature: OSType = 0x61766931 // 'avi1'

    /// 注册(替换)全局热键。换热键 = 先 Unregister 再注册(PLAN §2.1)。主线程调用。
    func register(_ hotkey: Hotkey, handler: @escaping @MainActor () -> Void) throws {
        unregisterAll()
        self.handler = handler
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            self.handler = nil
            throw HotkeyError.registrationFailed(status)
        }
        hotKeyRef = ref
    }

    func unregisterAll() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        handler = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // @convention(c) 回调不能捕获上下文 → self 走 userData 指针进来。
        // Carbon 热键事件在主 runloop 派发,assumeIsolated 安全(PLAN §2.1 Swift 6 坑)。
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.handler?()
            }
            return noErr
        }
        let status = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef
        )
        guard status == noErr else {
            throw HotkeyError.registrationFailed(status)
        }
    }
}
