import AppKit
import Carbon.HIToolbox

/// 全局快捷键定义。modifiers 存 Carbon mask(cmdKey=0x0100 等);
/// 与 NSEvent.ModifierFlags 位布局不同,必须按位翻译,不能 raw cast(实测,FINDINGS §3.6)。
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// 默认 ⌃⌥V:避开 Spotlight 的 ⌘Space(PLAN §2.1)
    public static let defaultToggle = Hotkey(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    public enum ValidationError: LocalizedError, Equatable {
        case modifierOnly
        case optionOnlyForbidden // macOS 15+ 禁 option-only/option+shift-only(-9868,grill #10)
        case noModifier

        public var errorDescription: String? {
            switch self {
            case .modifierOnly: "请再按一个字母/数字键"
            case .optionOnlyForbidden: "系统不允许仅用 ⌥/⇧ 的组合,请加 ⌃ 或 ⌘"
            case .noModifier: "请至少加一个修饰键(⌃⌥⌘⇧)"
            }
        }
    }

    /// 录制到的组合是否可注册(grill #10:option-only / option+shift-only 会被 macOS 15+ 拒)
    public static func validate(keyCode: UInt32?, carbonModifiers: UInt32) throws {
        let hasControl = carbonModifiers & UInt32(controlKey) != 0
        let hasCommand = carbonModifiers & UInt32(cmdKey) != 0
        let hasOption = carbonModifiers & UInt32(optionKey) != 0
        let hasShift = carbonModifiers & UInt32(shiftKey) != 0
        guard keyCode != nil else { throw ValidationError.modifierOnly }
        guard hasControl || hasCommand || hasOption || hasShift else { throw ValidationError.noModifier }
        if !hasControl && !hasCommand && (hasOption || hasShift) {
            throw ValidationError.optionOnlyForbidden
        }
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    public var displayString: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName
    }

    /// 从录制到的 NSEvent 构造(keyCode + 修饰键翻译);修饰键单独按下时 event.keyCode 无意义,由调用方保证是完整组合
    public init(event: NSEvent) {
        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = Hotkey.carbonModifiers(from: event.modifierFlags)
    }

    public var keyName: String {
        if let name = Hotkey.keyNames[Int(keyCode)] { return name }
        // 字母/数字:用当前键盘布局翻译 keyCode → 字符
        if let translated = Hotkey.character(for: keyCode) { return translated.uppercased() }
        return "#\(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9",
        kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let result = layoutData.withUnsafeBytes { raw -> OSStatus in
            let keyLayout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(
                keyLayout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, chars.count, &length, &chars
            )
        }
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Carbon RegisterEventHotKey 封装。收全局热键不需要任何 TCC 权限(实测,FINDINGS §1-2);
/// 前提:真 .app bundle + 活的 NSApplication runloop(LSUIElement + .accessory)。
@MainActor
public final class HotkeyManager {
    public enum HotkeyError: LocalizedError {
        case registrationFailed(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .registrationFailed(let status): "RegisterEventHotKey err=\(status)"
            }
        }
    }

    public init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var cancelKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?
    private var cancelHandler: (@MainActor () -> Void)?

    private static let signature: OSType = 0x61766931 // 'avi1'
    private static let toggleID: UInt32 = 1
    private static let cancelID: UInt32 = 2

    /// 注册(替换)全局热键。换热键 = 先 Unregister 再注册(PLAN §2.1)。主线程调用。
    public func register(_ hotkey: Hotkey, handler: @escaping @MainActor () -> Void) throws {
        unregisterAll()
        self.handler = handler
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.toggleID)
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

    /// grill #7:仅录音期间临时注册 Esc(无修饰键)为取消键——停止录音即注销,
    /// 把「系统级占用 Esc」的窗口压到最短。
    public func registerCancelKey(handler: @escaping @MainActor () -> Void) throws {
        unregisterCancelKey()
        cancelHandler = handler
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.cancelID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), 0, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            cancelHandler = nil
            throw HotkeyError.registrationFailed(status)
        }
        cancelKeyRef = ref
    }

    public func unregisterCancelKey() {
        if let cancelKeyRef {
            UnregisterEventHotKey(cancelKeyRef)
        }
        cancelKeyRef = nil
        cancelHandler = nil
    }

    public func unregisterAll() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        handler = nil
        unregisterCancelKey()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // @convention(c) 回调不能捕获上下文 → self 走 userData 指针进来。
        // Carbon 热键事件在主 runloop 派发,assumeIsolated 安全(PLAN §2.1 Swift 6 坑)。
        // 按 EventHotKeyID 路由:1=toggle,2=cancel(Esc)。
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let firedID = hotKeyID.id
            MainActor.assumeIsolated {
                switch firedID {
                case HotkeyManager.toggleID: manager.handler?()
                case HotkeyManager.cancelID: manager.cancelHandler?()
                default: break
                }
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
