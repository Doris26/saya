import AIVoiceInputCore
import AVFoundation
import AppKit
import SwiftUI
import UserNotifications

/// 首启引导:欢迎 → 麦克风 → 辅助功能 → 通知 → API Key → 完成(PLAN §2.4)。
/// 权限无系统回调 → 用 Timer 轮询状态,变绿自动前进。
struct OnboardingView: View {
    let coordinator: AppCoordinator
    let onFinish: () -> Void

    @State private var step = 0
    @State private var micGranted = false
    @State private var axGranted = false
    @State private var apiKeyField = ""
    @State private var poll: Timer?

    private var settings: SettingsStore { coordinator.settings }
    private let permissions = PermissionManager()

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case 0:
                stepView(icon: "mic.circle.fill", title: "欢迎使用 AI Voice Input",
                         body: "按全局热键说话,自动转写并输入到光标处。下面几步配置权限与 API Key。",
                         action: "开始") { step = 1 }
            case 1:
                stepView(icon: "mic.fill", title: "麦克风权限",
                         body: micGranted ? "已授权 ✓" : "用于录制语音。点下面按钮授权。",
                         action: micGranted ? "下一步" : "授权麦克风") {
                    if micGranted { step = 2 } else {
                        Task { _ = await permissions.requestMicAccess(); refresh() }
                    }
                }
            case 2:
                stepView(icon: "accessibility", title: "辅助功能权限",
                         body: axGranted ? "已授权 ✓" : "用于把文字输入到当前 App。请在系统设置里打开开关(会自动检测)。",
                         action: axGranted ? "下一步" : "打开系统设置") {
                    if axGranted { step = 3 } else { permissions.openAccessibilitySettings() }
                }
            case 3:
                stepView(icon: "bell.badge", title: "通知权限",
                         body: "注入结果、设备切换等提示需要通知。",
                         action: "允许通知") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound])
                        step = 4
                    }
                }
            case 4:
                stepView(icon: "globe", title: "触发方式:fn 单键",
                         body: "默认按一下 🌐 fn(地球键)开始录音,再按一下停止。\n\n⚠️ macOS 默认单按 fn 是听写/emoji。请到 系统设置 → 键盘 → 「按下 🌐 键用于」改为「无操作」,否则会和系统冲突。也可稍后在设置里改用组合键。",
                         action: "打开键盘设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                    step = 5
                }
            case 5:
                VStack(spacing: 12) {
                    Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(.tint)
                    Text("OpenAI API Key").font(.title2).bold()
                    SecureField("sk-…", text: $apiKeyField).frame(width: 300)
                    Button("保存并完成") {
                        if !apiKeyField.isEmpty { settings.apiKey = apiKeyField }
                        settings.launchAtLogin = true // grill #20:默认开
                        finish()
                    }
                    .disabled(apiKeyField.isEmpty && settings.effectiveAPIKey.isEmpty)
                    Button("稍后设置") { settings.launchAtLogin = true; finish() }
                        .buttonStyle(.link)
                }
            default:
                EmptyView()
            }
        }
        .padding(40)
        .frame(width: 460, height: 320)
        .onAppear { startPolling() }
        .onDisappear { poll?.invalidate() }
    }

    private func stepView(icon: String, title: String, body: String, action: String, act: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2).bold()
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(action, action: act).buttonStyle(.borderedProminent)
        }
    }

    private func startPolling() {
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func refresh() {
        micGranted = permissions.micPermission == .granted
        axGranted = permissions.axTrusted
    }

    private func finish() {
        poll?.invalidate()
        onFinish()
    }
}
