// M3 两进程验收 harness 接收器(PLAN §4 M3 命名工作项;grill #13)。
// 一个可获焦的 NSTextView 窗口,文本每次变化都 dump 到 AIVI_RECEIVER_OUT 文件,
// agent 由此断言「exact payload 真的落字」——不是 consuming-tap 自我认证。
//
// 模式(命令行参数):
//   (无)            普通 NSTextView
//   --secure         NSSecureTextField 获焦(P0#2 密码框场景)
//   --secure-input   EnableSecureEventInput(grill #4 场景,模拟 Terminal Secure Keyboard Entry)
//   --swallow-cmdv   吞掉 ⌘V 不粘贴(模拟重映射 ⌘V 的终端;P0#1 找回场景)
import AppKit
import Carbon.HIToolbox

let args = CommandLine.arguments
let outPath = ProcessInfo.processInfo.environment["AIVI_RECEIVER_OUT"] ?? "/tmp/aivi_receiver_out.txt"

func dump(_ text: String) {
    try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
}

final class Delegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var textView: NSTextView?
    var secureField: NSSecureTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 200, y: 200, width: 480, height: 240)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "InjectReceiver"
        window.level = .floating

        if args.contains("--secure") {
            let field = NSSecureTextField(frame: NSRect(x: 20, y: 100, width: 440, height: 24))
            field.delegate = self
            window.contentView?.addSubview(field)
            secureField = field
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(field)
        } else {
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            let view = SwallowTextView(frame: scroll.bounds)
            view.swallowCmdV = args.contains("--swallow-cmdv")
            view.isRichText = false
            view.delegate = self
            scroll.documentView = view
            window.contentView?.addSubview(scroll)
            textView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }

        if args.contains("--secure-input") {
            EnableSecureEventInput()
        }

        NSApp.activate(ignoringOtherApps: true)
        dump("") // READY 信号:文件存在且为空
    }

    func textDidChange(_ notification: Notification) {
        dump(textView?.string ?? "")
    }

    func controlTextDidChange(_ notification: Notification) {
        dump(secureField?.stringValue ?? "")
    }
}

/// --swallow-cmdv:⌘V 被消费但不粘贴(模拟重映射终端)
final class SwallowTextView: NSTextView {
    var swallowCmdV = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if swallowCmdV,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            return true // 吞掉
        }
        return super.performKeyEquivalent(with: event)
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
