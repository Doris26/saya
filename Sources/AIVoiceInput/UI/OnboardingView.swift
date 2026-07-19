import AIVoiceInputCore
import AVFoundation
import AppKit
import SwiftUI
import UserNotifications

/// 首启引导:欢迎 → 麦克风 → 辅助功能 → 通知 → 触发方式 → API Key → 完成(PLAN §2.4)。
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
        let l = coordinator.l10n
        VStack(spacing: 20) {
            switch step {
            case 0:
                stepView(icon: "mic.circle.fill", title: l.t(.obWelcomeTitle),
                         body: l.t(.obWelcomeBody), action: l.t(.obStart)) { step = 1 }
            case 1:
                stepView(icon: "mic.fill", title: l.t(.obMicTitle),
                         body: micGranted ? l.t(.obMicBodyGranted) : l.t(.obMicBody),
                         action: micGranted ? l.t(.obNext) : l.t(.obGrantMic)) {
                    if micGranted { step = 2 } else {
                        Task { _ = await permissions.requestMicAccess(); refresh() }
                    }
                }
            case 2:
                stepView(icon: "accessibility", title: l.t(.obAXTitle),
                         body: axGranted ? l.t(.obAXBodyGranted) : l.t(.obAXBody),
                         action: axGranted ? l.t(.obNext) : l.t(.obOpenSettings)) {
                    if axGranted { step = 3 } else { permissions.openAccessibilitySettings() }
                }
            case 3:
                stepView(icon: "bell.badge", title: l.t(.obNotifTitle),
                         body: l.t(.obNotifBody), action: l.t(.obAllowNotif)) {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound])
                        step = 4
                    }
                }
            case 4:
                stepView(icon: "globe", title: l.t(.obTriggerTitle),
                         body: l.t(.obTriggerBody), action: l.t(.obOpenKeyboard)) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                    step = 5
                }
            case 5:
                VStack(spacing: 12) {
                    Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(.tint)
                    Text(l.t(.obKeyTitle)).font(.title2).bold()
                    SecureField(l.t(.apiKeyPlaceholderEmpty), text: $apiKeyField).frame(width: 300)
                    Button(l.t(.obSaveFinish)) {
                        if !apiKeyField.isEmpty { settings.apiKey = apiKeyField }
                        settings.launchAtLogin = true // grill #20:默认开
                        finish()
                    }
                    .disabled(apiKeyField.isEmpty && settings.effectiveAPIKey.isEmpty)
                    Button(l.t(.obLater)) { settings.launchAtLogin = true; finish() }
                        .buttonStyle(.link)
                }
            default:
                EmptyView()
            }
        }
        .padding(40)
        .frame(width: 480, height: 340)
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
