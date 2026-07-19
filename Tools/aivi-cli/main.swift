// M3 harness 注入驱动 CLI:用生产 TextInjector(不是重新内联的拷贝,skill 214)驱动注入,
// 供两进程验收脚本使用。
//
// 子命令:
//   probe                       打印 AX trusted / secure-input / IME 状态
//   pbcount                     打印 NSPasteboard.general.changeCount
//   pbget                       打印当前剪贴板字符串
//   pbset <text>                写剪贴板
//   inject <text> [--method paste|type] [--delay <s>] [--no-snapshot]
//                               capture focus → (delay) → inject,打印 outcome
import AIVoiceInputCore
import AppKit
import Carbon.HIToolbox

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: aivi-cli probe|pbcount|pbget|pbset|inject ...")
    exit(2)
}

@MainActor
func run() async {
    switch args[1] {
    case "probe":
        print("axTrusted=\(AXIsProcessTrusted())")
        print("secureInput=\(IsSecureEventInputEnabled())")
    case "pbcount":
        print(NSPasteboard.general.changeCount)
    case "pbget":
        print(NSPasteboard.general.string(forType: .string) ?? "<nil>")
    case "pbset":
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(args.count > 2 ? args[2] : "", forType: .string)
        print("ok")
    case "inject":
        guard args.count > 2 else { print("missing text"); exit(2) }
        let text = args[2]
        var method: TextInjector.Method = .auto
        if let methodIndex = args.firstIndex(of: "--method"), methodIndex + 1 < args.count {
            method = TextInjector.Method(rawValue: args[methodIndex + 1]) ?? .auto
        }
        var delay: Double = 0
        if let delayIndex = args.firstIndex(of: "--delay"), delayIndex + 1 < args.count {
            delay = Double(args[delayIndex + 1]) ?? 0
        }
        if let chunkIndex = args.firstIndex(of: "--chunk"), chunkIndex + 1 < args.count {
            TextInjector.typeChunkUTF16 = Int(args[chunkIndex + 1]) ?? 16
        }
        let injector = TextInjector()
        let snapshot = args.contains("--no-snapshot") ? nil : injector.captureFocus()
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        do {
            let outcome = try await injector.inject(text, method: method, expectedFocus: snapshot)
            print("outcome=\(outcome)")
            // 粘贴法的剪贴板恢复是 fire-and-forget Task,等它跑完再退进程
            try? await Task.sleep(for: .milliseconds(TextInjector.pasteRestoreDelayMS + 300))
        } catch {
            print("error=\(error)")
            exit(1)
        }
    default:
        print("unknown subcommand \(args[1])")
        exit(2)
    }
    exit(0)
}

// CLI 也要 runloop(CGEvent post/AX 需要);用 NSApplication 但不激活
Task { @MainActor in
    await run()
}
NSApplication.shared.run()
