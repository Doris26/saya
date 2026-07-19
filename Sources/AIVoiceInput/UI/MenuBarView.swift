import AIVoiceInputCore
import AppKit
import SwiftUI

/// 菜单栏下拉内容(MenuBarExtra 默认 .menu 样式:Text 渲染为不可点条目)。
struct MenuBarView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Text(coordinator.statusLine)
        if let note = coordinator.lastNote {
            Text(note)
        }
        if let triggerNote = coordinator.triggerNote {
            Text("⚠️ \(triggerNote)")
        }
        Text("触发 \(coordinator.triggerDisplay) · 已触发 \(coordinator.hotkeyFireCount) 次")

        Divider()

        switch coordinator.state {
        case .recording:
            Button("停止录音") { coordinator.toggleRecording() }
            Button("取消录音(Esc)") { coordinator.cancel() }
        case .transcribing:
            Button("取消转写") { coordinator.cancel() }
        default:
            Button("开始录音") { coordinator.toggleRecording() }
        }

        // 【P0#1】唯一找回路径:注入成功不可探测,转写始终可从这里复制
        if let transcript = coordinator.lastTranscript {
            Divider()
            Text("最近转写:\(transcript.count > 40 ? String(transcript.prefix(40)) + "…" : transcript)")
            Button("复制上次转写") { coordinator.copyLastTranscript() }
        }
        if coordinator.failedRecordingURL != nil {
            Button("重试转写") { coordinator.retryTranscription() }
            Button("在访达中显示保留音频") { coordinator.revealLastRecording() }
        }

        Divider()

        // 计费追踪:本月/今日用量与花费
        let usage = coordinator.usageSummary
        Text(String(format: "本月 %.0f 分钟 · ¥%.2f($%.3f)",
                    usage.monthMinutes, usage.monthCostCNY, usage.monthCostUSD))
        Text(String(format: "今日 %.0f 分钟 · ¥%.2f", usage.todayMinutes, usage.todayCostCNY))

        Divider()

        SettingsLink { Text("设置…") }
            .keyboardShortcut(",")

        Divider()

        Button("退出 Saya") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
