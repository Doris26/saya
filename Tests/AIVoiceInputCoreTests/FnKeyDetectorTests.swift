import Testing

@testable import AIVoiceInputCore

/// fn 边沿检测状态机单测(mock flagsChanged/keyDown 序列)。
/// 真按 fn 的 GUI 实测由 owner 在自己机器验;这里把逻辑做扎实。
@Suite struct FnKeyDetectorTests {
    /// 收集触发次数的辅助
    private func detector(maxTap: Double = 1.0, debounce: Double = 0.15) -> (FnKeyDetector, () -> Int) {
        final class Counter { var n = 0 }
        let counter = Counter()
        let det = FnKeyDetector(maxTapDuration: maxTap, debounceInterval: debounce) { counter.n += 1 }
        return (det, { counter.n })
    }

    @Test func cleanTapTriggers() {
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0))
        det.handle(.fnUp(at: 0.2))
        #expect(count() == 1)
    }

    @Test func fnPlusOtherKeyDoesNotTrigger() {
        // fn+F1 之类组合键:放行给系统,不触发
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0))
        det.handle(.otherKey)
        det.handle(.fnUp(at: 0.1))
        #expect(count() == 0)
    }

    @Test func fnPlusModifierDoesNotTrigger() {
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0))
        det.handle(.otherKey) // 监听层把 fn+cmd 的 cmd 变化也翻译成 otherKey
        det.handle(.fnUp(at: 0.15))
        #expect(count() == 0)
    }

    @Test func longHoldDoesNotTrigger() {
        // 按住 fn 发呆 > maxTapDuration → 不算 tap
        let (det, count) = detector(maxTap: 1.0)
        det.handle(.fnDown(at: 0.0))
        det.handle(.fnUp(at: 1.5))
        #expect(count() == 0)
    }

    @Test func twoTapsTriggerTwice() {
        // 两次独立 tap = start + stop
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0)); det.handle(.fnUp(at: 0.1))
        det.handle(.fnDown(at: 1.0)); det.handle(.fnUp(at: 1.1))
        #expect(count() == 2)
    }

    @Test func debounceSuppressesBounce() {
        // 物理抖动:两次 tap 间隔 < debounceInterval → 只认第一次
        let (det, count) = detector(debounce: 0.15)
        det.handle(.fnDown(at: 0.0)); det.handle(.fnUp(at: 0.05)) // tap @0.05
        det.handle(.fnDown(at: 0.08)); det.handle(.fnUp(at: 0.12)) // @0.12,距上次 0.07 < 0.15 → 抑制
        #expect(count() == 1)
    }

    @Test func fnUpWithoutDownIgnored() {
        // 挂载瞬间可能收到孤立 fnUp(用户挂载时正按着 fn)→ 不崩不误触
        let (det, count) = detector()
        det.handle(.fnUp(at: 0.5))
        #expect(count() == 0)
    }

    @Test func otherKeyBeforeFnDownIrrelevant() {
        // fn 没按下时的普通打字不影响后续 tap
        let (det, count) = detector()
        det.handle(.otherKey)
        det.handle(.fnDown(at: 1.0))
        det.handle(.fnUp(at: 1.1))
        #expect(count() == 1)
    }

    @Test func resetClearsHalfPressedState() {
        // 模式切换/重挂:reset 后残留的 fnDown 不该在下次 fnUp 误触发
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0))
        det.reset()
        det.handle(.fnUp(at: 0.2))
        #expect(count() == 0)
    }

    @Test func negativeDurationIgnored() {
        // 时钟回绕/乱序时间戳 → 不触发(duration < 0 守卫)
        let (det, count) = detector()
        det.handle(.fnDown(at: 1.0))
        det.handle(.fnUp(at: 0.5))
        #expect(count() == 0)
    }

    @Test func modifierAfterFnUpDoesNotAffectNextTap() {
        // otherKey 出现在 fn 松开之后(fnDownAt=nil)→ 不把下一次 fn 标记成组合
        let (det, count) = detector()
        det.handle(.fnDown(at: 0.0)); det.handle(.fnUp(at: 0.1)) // tap 1
        det.handle(.otherKey) // 录音中用户打字
        det.handle(.fnDown(at: 1.0)); det.handle(.fnUp(at: 1.1)) // tap 2 应正常
        #expect(count() == 2)
    }
}
