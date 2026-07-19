import AIVoiceInputCore
import AppKit
import SwiftUI

/// 菜单栏下拉内容(MenuBarExtra 默认 .menu 样式:Text 渲染为不可点条目)。
struct MenuBarView: View {
    let coordinator: AppCoordinator

    var body: some View {
        let l = coordinator.l10n
        Text(coordinator.statusLine)
        if let note = coordinator.lastNote {
            Text(note)
        }
        if let triggerNote = coordinator.triggerNote {
            Text("⚠️ \(triggerNote)")
        }
        Text(l.t(.menuTriggerLine, coordinator.triggerDisplay, coordinator.hotkeyFireCount))

        Divider()

        switch coordinator.state {
        case .recording:
            Button(l.t(.menuStop)) { coordinator.toggleRecording() }
            Button(l.t(.menuCancelRecording)) { coordinator.cancel() }
        case .transcribing:
            Button(l.t(.menuCancelTranscribe)) { coordinator.cancel() }
        default:
            Button(l.t(.menuStart)) { coordinator.toggleRecording() }
        }

        // 【P0#1】唯一找回路径:注入成功不可探测,转写始终可从这里复制
        if let transcript = coordinator.lastTranscript {
            Divider()
            let shown = transcript.count > 40 ? String(transcript.prefix(40)) + "…" : transcript
            Text(l.t(.menuRecentTranscript, shown))
            Button(l.t(.menuCopyLast)) { coordinator.copyLastTranscript() }
        }
        if coordinator.failedRecordingURL != nil {
            Button(l.t(.menuRetry)) { coordinator.retryTranscription() }
            Button(l.t(.menuRevealAudio)) { coordinator.revealLastRecording() }
        }

        Divider()

        // 计费追踪:本月/今日用量与花费
        let usage = coordinator.usageSummary
        Text(l.t(.menuUsageMonth, usage.monthMinutes, usage.monthCostCNY, usage.monthCostUSD))
        Text(l.t(.menuUsageToday, usage.todayMinutes, usage.todayCostCNY, usage.todayCostUSD))

        Divider()

        SettingsLink { Text(l.t(.menuSettings)) }
            .keyboardShortcut(",")

        Divider()

        Button(l.t(.menuQuit)) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
