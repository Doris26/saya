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
            // 彩色 emoji 字形:在菜单栏(尤其刘海旁 / 一堆单色系统图标中)一眼可辨。
            Text(coordinator.state.menuBarGlyph)
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
}
