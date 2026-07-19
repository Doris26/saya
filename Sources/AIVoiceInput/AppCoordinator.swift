import AppKit
import Observation

/// App 全局状态。所有模块只被 AppCoordinator 编排,互相不引用(PLAN §1.2)。
enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case error(String)

    var menuBarSymbol: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .error: "mic.slash"
        }
    }

    var statusLine: String {
        switch self {
        case .idle: "空闲"
        case .recording: "录音中…"
        case .transcribing: "转写中…"
        case .error(let message): "错误:\(message)"
        }
    }
}

/// 唯一状态机与编排者。M0:状态空转 + 热键计数;M1 起接真录音。
@MainActor
@Observable
final class AppCoordinator {
    private(set) var state: AppState = .idle
    private(set) var hotkeyFireCount = 0
    let hotkey: Hotkey = .defaultToggle

    @ObservationIgnored private let hotkeyManager = HotkeyManager()

    init() {
        registerHotkey()
    }

    func toggleRecording() {
        switch state {
        case .idle, .error:
            state = .recording
            Log.app.info("state -> recording (M0 stub)")
        case .recording:
            state = .idle
            Log.app.info("state -> idle (M0 stub)")
        case .transcribing:
            // 转写期间 toggle 无操作;M2 起决定是否允许排队/取消
            Log.app.info("toggle ignored while transcribing")
        }
    }

    private func registerHotkey() {
        do {
            try hotkeyManager.register(hotkey) { [weak self] in
                guard let self else { return }
                hotkeyFireCount += 1
                Log.hotkey.info("hotkey fired count=\(self.hotkeyFireCount, privacy: .public)")
                toggleRecording()
            }
            Log.hotkey.info("registered \(self.hotkey.displayString, privacy: .public)")
        } catch {
            // 与其他 App 冲突时 RegisterEventHotKey 返回错误码,提示用户换键(PLAN §2.1)
            state = .error("热键注册失败(\(hotkey.displayString) 可能被其他 App 占用)")
            Log.hotkey.error("register failed: \(String(describing: error), privacy: .public)")
        }
    }
}
