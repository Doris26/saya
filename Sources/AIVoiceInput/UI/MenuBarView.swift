import AppKit
import SwiftUI

/// 菜单栏下拉内容(MenuBarExtra 默认 .menu 样式:Text 渲染为不可点条目)。
struct MenuBarView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Text(coordinator.state.statusLine)
        Text("热键 \(coordinator.hotkey.displayString) · 已触发 \(coordinator.hotkeyFireCount) 次")

        Divider()

        Button(coordinator.state == .recording ? "停止录音" : "开始录音") {
            coordinator.toggleRecording()
        }

        Divider()

        Button("设置…") {
            // M4: 设置窗口(General / Hotkey / Advanced)
        }
        .disabled(true)

        Divider()

        Button("退出 AI Voice Input") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
