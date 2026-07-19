import AppKit
import AVFoundation

/// 麦克风 + 辅助功能权限检测与引导(PLAN §2.4)。
@MainActor
final class PermissionManager {
    enum MicPermission {
        case granted, denied, undetermined
    }

    /// 用属性读态,不用 request 的返回值判断——非 GUI 进程 undetermined 态
    /// request 会返回 false 但不置 denied(实测,FINDINGS §6)
    var micPermission: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    func requestMicAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// M3:辅助功能授权(注入必需)
    var axTrusted: Bool { AXIsProcessTrusted() }

    func openSystemSettings(privacyPane pane: String) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let settingsURL = URL(string: url) {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    func openMicrophoneSettings() {
        openSystemSettings(privacyPane: "Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSystemSettings(privacyPane: "Privacy_Accessibility")
    }
}
