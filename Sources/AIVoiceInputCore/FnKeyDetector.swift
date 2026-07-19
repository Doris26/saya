import Foundation

/// fn(🌐 地球键)单键 toggle 的**纯状态机**——不碰任何系统 API,可完整单测。
/// 监听层(FnKeyMonitor)把 CGEventTap 的 flagsChanged/keyDown 翻译成 `Event` 喂进来。
///
/// 判定「单独按 fn 一下」= tap:fnDown → fnUp,期间**没有**其他键/修饰键(否则是 fn+X 组合,放行)。
/// 去抖:
///  - `maxTapDuration`:按住太久(> 阈值)不算 tap(防止「按着 fn 发呆」误触发)。
///  - `debounceInterval`:两次 tap 间隔太短(物理抖动/连击)只认第一次(防 start→立刻 stop 丢录音)。
public final class FnKeyDetector {
    public enum Event: Equatable {
        case fnDown(at: TimeInterval)
        case fnUp(at: TimeInterval)
        /// fn 按住期间出现的任意其他按键或修饰键 → 本次 fn 是组合键的一部分,不触发
        case otherKey
    }

    public var maxTapDuration: TimeInterval
    public var debounceInterval: TimeInterval
    private let onTap: () -> Void

    private var fnDownAt: TimeInterval?
    private var usedAsModifier = false
    private var lastTapAt: TimeInterval?

    public init(
        maxTapDuration: TimeInterval = 1.0,
        debounceInterval: TimeInterval = 0.15,
        onTap: @escaping () -> Void
    ) {
        self.maxTapDuration = maxTapDuration
        self.debounceInterval = debounceInterval
        self.onTap = onTap
    }

    public func handle(_ event: Event) {
        switch event {
        case .fnDown(let time):
            fnDownAt = time
            usedAsModifier = false
        case .otherKey:
            // 只有在 fn 已按下时,其他键才把本次 fn 标记为「组合键」
            if fnDownAt != nil { usedAsModifier = true }
        case .fnUp(let time):
            defer { fnDownAt = nil; usedAsModifier = false }
            guard let downAt = fnDownAt else { return }        // fnUp 无配对 fnDown → 忽略
            guard !usedAsModifier else { return }              // fn+X 组合 → 放行,不触发
            let duration = time - downAt
            guard duration >= 0, duration <= maxTapDuration else { return } // 长按/时钟回绕 → 不算 tap
            if let last = lastTapAt, time - last < debounceInterval { return } // 去抖
            lastTapAt = time
            onTap()
        }
    }

    /// 模式切换/重挂监听时复位内部状态(避免残留的半按状态误判)
    public func reset() {
        fnDownAt = nil
        usedAsModifier = false
        lastTapAt = nil
    }
}
