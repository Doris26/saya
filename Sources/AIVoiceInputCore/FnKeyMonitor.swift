import AppKit
import CoreGraphics

/// fn(🌐)单键 toggle 的监听层。CGEventTap **listen-only**(不消费事件——fn+其他键要放行给
/// 系统,单独 fn 也不拦,系统听写占用由 onboarding 提示用户设成「无操作」)。
///
/// fn 不是 Carbon 修饰键(RegisterEventHotKey 绑不了),只能从 flagsChanged 的
/// `maskSecondaryFn` 位边沿检测。边沿逻辑委托给可单测的 FnKeyDetector。
/// 需要辅助功能授权(已有);CGEventTap 被系统超时禁用时自动重挂。
@MainActor
public final class FnKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var detector: FnKeyDetector?
    private var fnWasDown = false

    public init() {}

    public var isRunning: Bool { eventTap != nil }

    /// 开始监听;每次「单独按 fn 一下」触发 onTap。返回 false = tap 创建失败(通常辅助功能未授权)。
    @discardableResult
    public func start(onTap: @escaping @MainActor () -> Void) -> Bool {
        stop()
        let detector = FnKeyDetector { onTap() }
        self.detector = detector
        fnWasDown = false

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.process(type: type, event: event)
            }
            return Unmanaged.passUnretained(event) // listen-only:原样放行
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("FnKeyMonitor: CGEvent.tapCreate failed (辅助功能未授权?)")
            self.detector = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        Log.hotkey.info("FnKeyMonitor started (fn toggle mode)")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        detector?.reset()
        detector = nil
        fnWasDown = false
    }

    private func process(type: CGEventType, event: CGEvent) {
        // 系统超时/用户输入禁用了 tap → 重新启用(PLAN §2.1 CGEventTap 坑)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let seconds = TimeInterval(event.timestamp) / 1_000_000_000 // ns → s,单调
        switch type {
        case .flagsChanged:
            let fnDown = event.flags.contains(.maskSecondaryFn)
            // 其他修饰键(cmd/opt/ctrl/shift)在 fn 按住期间变化 → 组合键
            let otherModifier = !event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            if fnDown && !fnWasDown {
                detector?.handle(.fnDown(at: seconds))
            } else if !fnDown && fnWasDown {
                detector?.handle(.fnUp(at: seconds))
            } else if fnDown && otherModifier {
                detector?.handle(.otherKey)
            }
            fnWasDown = fnDown
        case .keyDown:
            // fn 按住期间的任意实体按键 → 组合键(如 fn+F1、fn+←)
            detector?.handle(.otherKey)
        default:
            break
        }
    }
}
