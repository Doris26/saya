import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 焦点快照:录音停止时(用户按热键=意图锚点)捕获,注入前 recheck(grill #6)。
public struct FocusSnapshot {
    public let appPID: pid_t
    public let bundleID: String?
    public let elementRef: AXUIElement?
    public let windowRef: AXUIElement?
}

/// 文字注入:剪贴板+⌘V 主 / CGEvent Unicode 打字备(PLAN §2.2)。
/// 注入安全链顺序:SecureEventInput → AX secure-field → 焦点 recheck → IME gate → 修饰键释放 → post。
@MainActor
public final class TextInjector {
    public enum Method: String, Sendable {
        case paste, type, auto
    }

    /// 注入结果语义(P0#1/P0#2):secure 拒注 ≠ 失败;粘贴成功不可探测,只报「已尝试」
    public enum Outcome: Equatable, Sendable {
        /// 已 post 注入事件(成功与否不可探测——找回路径=菜单)
        case attempted(Method)
        /// secure 上下文拒注(P0#2:绝不进剪贴板,transcript 只留菜单)
        case refusedSecureContext(culprit: String?)
        /// 焦点变了/AX 未授权 → 文本落剪贴板(带 ConcealedType,N 分钟自动清)
        case fellBackToClipboard(reasonKey: LocKey)
    }

    public enum InjectorError: LocalizedError {
        case accessibilityNotTrusted

        public var errorDescription: String? {
            switch self {
            case .accessibilityNotTrusted: "辅助功能未授权"
            }
        }
    }

    /// 打字法分块:~20 UTF-16/事件的说法未验证(FINDINGS §2.2)→ 默认保守 16,
    /// harness 实测(bin/m3 验收)后可调;块间延迟 5ms。
    public static var typeChunkUTF16 = 16
    public static let typeInterChunkDelayUS: UInt32 = 5000
    /// 粘贴后恢复剪贴板的等待(目标 App 异步读剪贴板,过早恢复→粘到旧内容,实测 ~400ms 安全)
    public static let pasteRestoreDelayMS = 400
    /// 剪贴板兜底自动清扫延迟(grill #25)
    public static let fallbackClearSeconds: TimeInterval = 120

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    public init() {}

    // MARK: - 焦点快照(grill #6)

    public func captureFocus() -> FocusSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var element: AXUIElement?
        var window: AXUIElement?
        if AXIsProcessTrusted() {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success {
                element = (focusedRef as! AXUIElement)
                var windowRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element!, kAXWindowAttribute as CFString, &windowRef) == .success {
                    window = (windowRef as! AXUIElement)
                }
            }
        }
        return FocusSnapshot(
            appPID: app.processIdentifier, bundleID: app.bundleIdentifier,
            elementRef: element, windowRef: window
        )
    }

    // MARK: - 注入主入口

    public func inject(_ text: String, method: Method, expectedFocus: FocusSnapshot?) async throws -> Outcome {
        guard AXIsProcessTrusted() else { throw InjectorError.accessibilityNotTrusted }

        // 链 1:SecureEventInput 无条件 gate(grill #4)——Terminal Secure Keyboard Entry/密码管理器
        if IsSecureEventInputEnabled() {
            let culprit = Self.secureInputCulpritName()
            Log.inject.info("refused: secure event input enabled by \(culprit ?? "unknown", privacy: .public)")
            return .refusedSecureContext(culprit: culprit)
        }

        // 链 2:AX secure-field 次级信号(P0#2:拒注不落剪贴板)
        if let focused = currentFocusedElement(), Self.isSecureField(focused) {
            Log.inject.info("refused: focused element is secure field")
            return .refusedSecureContext(culprit: nil)
        }

        // 链 3:焦点 recheck(element+window+app 级,grill #6)
        if let expected = expectedFocus, !focusMatches(expected) {
            Log.inject.info("focus changed since capture -> clipboard fallback")
            fallbackToClipboard(text)
            return .fellBackToClipboard(reasonKey: .reasonFocusChanged)
        }

        // 链 4:CJK IME gate(grill #11)——IME 激活时打字法会进拼音组合缓冲,强制走粘贴
        var effectiveMethod = method == .auto ? Method.paste : method
        if effectiveMethod == .type, Self.cjkInputSourceActive() {
            Log.inject.info("CJK IME active -> forcing paste method")
            effectiveMethod = .paste
        }

        // 链 5:等物理修饰键释放(≤500ms,grill #18)——短 clip 时用户可能还按着 ⌃⌥
        await Self.waitForModifierRelease()

        switch effectiveMethod {
        case .paste, .auto:
            pasteInject(text)
            return .attempted(.paste)
        case .type:
            typeInject(text)
            return .attempted(.type)
        }
    }

    /// 剪贴板兜底(注入失败类专用;P0#2:secure 拒注不得调这里)
    public func fallbackToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedType) // 守规矩的剪贴板管理器会忽略
        let markCount = pasteboard.changeCount
        // grill #25:N 分钟后 changeCount 未变则自动清
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fallbackClearSeconds))
            if NSPasteboard.general.changeCount == markCount {
                NSPasteboard.general.clearContents()
                Log.inject.info("fallback clipboard auto-cleared")
            }
        }
    }

    // MARK: - 粘贴法

    private func pasteInject(_ text: String) {
        let pasteboard = NSPasteboard.general
        // 快照(materialized flavor only——promised/lazy 数据拿不到,有损,FINDINGS §2.2)
        let snapshot: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var flavors: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { flavors[type] = data }
            }
            return flavors
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)

        postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // 延迟恢复:目标 App 异步读剪贴板(过早恢复→粘空/旧)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.pasteRestoreDelayMS))
            let pb = NSPasteboard.general
            pb.clearContents()
            for flavors in snapshot where !flavors.isEmpty {
                let item = NSPasteboardItem()
                for (type, data) in flavors { item.setData(data, forType: type) }
                pb.writeObjects([item])
            }
            Log.inject.info("pasteboard restored (\(snapshot.count, privacy: .public) items)")
        }
    }

    // MARK: - 打字法

    private func typeInject(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            let end = min(index + Self.typeChunkUTF16, utf16.count)
            var chunk = Array(utf16[index..<end])
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            usleep(Self.typeInterChunkDelayUS) // 块间延迟防丢字/乱序
            index = end
        }
    }

    // MARK: - 安全链探针

    private func currentFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success else {
            return nil
        }
        return (focusedRef as! AXUIElement)
    }

    private static func isSecureField(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == kAXSecureTextFieldSubrole as String {
            return true
        }
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role.lowercased().contains("secure") {
            return true
        }
        return false
    }

    private func focusMatches(_ expected: FocusSnapshot) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == expected.appPID else {
            return false
        }
        // element/window 级比对(AXUIElement 同一底层对象 CFEqual 为真);快照拿不到时降级 app 级
        if let expectedElement = expected.elementRef {
            guard let current = currentFocusedElement(), CFEqual(current, expectedElement) else { return false }
        }
        return true
    }

    /// SecureEventInput culprit(通知点名用,grill #4)
    private static func secureInputCulpritName() -> String? {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = dict["kCGSSessionSecureInputPID"] as? Int32 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// CJK IME 激活?(grill #11)
    private static func cjkInputSourceActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        guard let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return false }
        let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String] ?? []
        return langs.contains { lang in
            lang.hasPrefix("zh") || lang.hasPrefix("ja") || lang.hasPrefix("ko")
        }
    }

    /// 物理修饰键释放等待(grill #18)
    private static func waitForModifierRelease() async {
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        usleep(30000)
        keyUp.post(tap: .cghidEventTap)
    }
}
