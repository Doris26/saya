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
            Image(systemName: coordinator.state.menuBarSymbol)
        }
    }
}
