import Foundation

/// 录音 HUD 浮层的**纯状态→内容映射**(不碰 AppKit,可完整单测)。
/// 控制器(RecordingHUDController)据此决定浮窗显示/隐藏与胶囊内容。

public enum HUDPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case injecting
    case error
}

public enum HUDContent: Equatable, Sendable {
    case hidden
    case recording       // 🔴 正在听… + 计时 + 波形(细节由 view 读实时数据)
    case transcribing    // ⏳ 转写中…
    case done            // ✓ 已输入(注入完成后短暂闪现再淡出)

    public var isVisible: Bool { self != .hidden }
}

public enum HUDPresenter {
    /// - Parameters:
    ///   - phase: 当前状态机阶段
    ///   - justCompleted: 是否刚注入完成(injecting→idle 的 ~1s 闪现窗口)
    ///   - enabled: 用户是否开启 HUD(设置开关,默认开)
    public static func content(phase: HUDPhase, justCompleted: Bool, enabled: Bool) -> HUDContent {
        guard enabled else { return .hidden }
        switch phase {
        case .recording:
            return .recording
        case .transcribing, .injecting:
            return .transcribing
        case .idle:
            return justCompleted ? .done : .hidden   // 不常驻:idle 且无刚完成 → 隐藏
        case .error:
            return .hidden                            // 错误走菜单栏,不打扰浮层
        }
    }

    /// averagePower(dBFS,约 −60…0)→ 波形高度 0…1。静音 ~−48→0.2,正常语音 −17→0.72。
    public static func normalizedLevel(db: Float) -> Float {
        max(0, min(1, (db + 60) / 60))
    }
}
