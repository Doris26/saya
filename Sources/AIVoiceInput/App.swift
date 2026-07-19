import AIVoiceInputCore
import SwiftUI

// 入口文件不叫 main.swift:`@main` + main.swift 会触发
// "'main' attribute cannot be used in a module that contains top-level code"(PLAN §5.2-2)
@main
struct AIVoiceInputApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            // 单色 template 图标,融入系统菜单栏审美;录音红/出错橙 tint 提示。
            // waveform(声波)= Saya 品牌形状,比普通 mic 更易在一排图标里辨认。
            Image(systemName: coordinator.state.menuBarSymbol)
                .foregroundStyle(menuBarTint(for: coordinator.state))
        }

        Settings {
            SettingsView(coordinator: coordinator)
        }

        // 首启引导窗(未配 key 或未授权时展示)
        Window("欢迎", id: "onboarding") {
            OnboardingView(coordinator: coordinator) {
                NSApplication.shared.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
    }

    /// 菜单栏图标着色:仅录音(红)/出错(橙)上色,其余跟随系统前景色(单色不扎眼)。
    private func menuBarTint(for state: AppState) -> Color {
        switch state {
        case .recording: .red
        case .error: .orange
        default: .primary
        }
    }
}
