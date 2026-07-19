import AIVoiceInputCore
import AppKit
import Observation
import SwiftUI

/// 非激活浮层面板。**canBecomeKey/Main = false 是硬约束**:HUD 出现绝不能抢走前台 App 的
/// 键盘焦点,否则破坏 M3 的注入目标(光标处注入依赖前台焦点不变)。
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// HUD 的可观察视图数据(控制器拥有;不反向引用 coordinator → 无 retain cycle)。
@MainActor
@Observable
final class HUDViewState {
    var content: HUDContent = .hidden
    var seconds: Int = 0
    var levels: [Float] = []   // 归一化 0…1 波形样本(最近若干个)
}

/// 屏幕底部居中的录音浮层控制器。状态驱动:按 fn 那一刻(state→recording)立即弹出,
/// 给「看不见的 fn 键」即时视觉回执;转写中/完成闪现;idle 淡出隐藏。
@MainActor
final class RecordingHUDController {
    private let panel: NonActivatingPanel
    private let viewState = HUDViewState()
    private var visible = false
    private let size = NSSize(width: 240, height: 56)

    init() {
        panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true          // 点击穿透(req #3)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: HUDView(state: viewState))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    /// 状态刷新入口。控制器只据 HUDContent 决定显隐;波形/计时的实时细节由 SwiftUI 读 viewState。
    func render(phase: HUDPhase, justCompleted: Bool, seconds: Int, levels: [Float], enabled: Bool) {
        let content = HUDPresenter.content(phase: phase, justCompleted: justCompleted, enabled: enabled)
        viewState.content = content
        viewState.seconds = seconds
        viewState.levels = levels
        if content.isVisible { show() } else { hide() }
    }

    private func show() {
        reposition()
        guard !visible else { return }
        visible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()   // 不激活、不抢 key(NOT makeKeyAndOrderFront)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15         // 快速淡入,别硬弹(req #5)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    /// 出现在有鼠标的那块屏(多屏,req #4),底部居中、Dock 上方
    private func reposition() {
        let screen = targetScreen()
        let vf = screen.visibleFrame     // 已排除 Dock/菜单栏
        let x = vf.midX - size.width / 2
        let y = vf.minY + 24             // 距可见区底部 24pt(Dock 上方)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// 浮层胶囊内容(纯 SwiftUI,读 HUDViewState)。
private struct HUDView: View {
    let state: HUDViewState

    var body: some View {
        capsuleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var capsuleContent: some View {
        switch state.content {
        case .hidden:
            EmptyView()
        case .recording:
            capsule {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Text("正在听…").font(.system(size: 12, weight: .medium))
                    Waveform(levels: state.levels)
                        .frame(width: 60, height: 18)
                    Text(timeString).font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .transcribing:
            capsule {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("转写中…").font(.system(size: 12, weight: .medium))
                }
            }
        case .done:
            capsule {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("已输入").font(.system(size: 12, weight: .medium))
                }
            }
        }
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .fixedSize()
    }

    private var timeString: String {
        String(format: "%d:%02d", state.seconds / 60, state.seconds % 60)
    }
}

/// 电平波形条(读归一化 levels)
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let barCount = 16
            let recent = Array(levels.suffix(barCount))
            let bars = recent + Array(repeating: Float(0), count: max(0, barCount - recent.count))
            let width = geo.size.width / CGFloat(barCount)
            HStack(alignment: .center, spacing: max(1, width * 0.25)) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(.tint)
                        .frame(height: max(2, CGFloat(bars[i]) * geo.size.height))
                }
            }
            .frame(height: geo.size.height, alignment: .center)
        }
    }
}
