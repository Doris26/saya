import AppKit
import Testing

@testable import AIVoiceInputCore

/// TextInjector 中不依赖 GUI 焦点的逻辑单测。端到端「落字进真实 App」需 Aqua 会话 +
/// Accessibility 授权,由 owner 在 M3 验收会话用 bin/m3_harness.sh 跑(agent 的 Background
/// session 不驱动真实窗口焦点,只能测机制,见 docs/FINDINGS §5)。
@MainActor
@Suite struct TextInjectorTests {
    @Test func outcomeEquatable() {
        #expect(TextInjector.Outcome.attempted(.paste) == .attempted(.paste))
        #expect(TextInjector.Outcome.attempted(.paste) != .attempted(.type))
        #expect(TextInjector.Outcome.refusedSecureContext(culprit: nil) == .refusedSecureContext(culprit: nil))
        #expect(TextInjector.Outcome.refusedSecureContext(culprit: "Terminal") != .refusedSecureContext(culprit: nil))
    }

    @Test func defaultChunkIsConservative() {
        // ~20 UTF-16/事件未验证(FINDINGS §2.2)→ 默认保守 16,harness 实测后可调
        #expect(TextInjector.typeChunkUTF16 == 16)
    }

    @Test func fallbackToClipboardMarksConcealedAndSetsText() {
        let injector = TextInjector()
        let sentinel = "FALLBACK-中文-\(UUID().uuidString)"
        injector.fallbackToClipboard(sentinel)
        let pasteboard = NSPasteboard.general
        #expect(pasteboard.string(forType: .string) == sentinel)
        // ConcealedType 标记:守规矩的剪贴板管理器(Paste/Maccy)据此忽略(grill #25)
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let types = pasteboard.pasteboardItems?.first?.types ?? []
        #expect(types.contains(concealed))
    }

    @Test func methodRawValues() {
        #expect(TextInjector.Method(rawValue: "paste") == .paste)
        #expect(TextInjector.Method(rawValue: "type") == .type)
        #expect(TextInjector.Method(rawValue: "auto") == .auto)
        #expect(TextInjector.Method(rawValue: "bogus") == nil)
    }
}
