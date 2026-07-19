import Testing

@testable import AIVoiceInputCore

/// HUD 状态→内容映射单测(状态×刚完成×开关 → 可见性)。真实浮层显示 owner 自测。
@Suite struct HUDPresenterTests {
    @Test func recordingShowsRecording() {
        // 按 fn 那一刻(state=recording)立即显示 recording,不等声音
        #expect(HUDPresenter.content(phase: .recording, justCompleted: false, enabled: true) == .recording)
    }

    @Test func transcribingAndInjectingShowTranscribing() {
        #expect(HUDPresenter.content(phase: .transcribing, justCompleted: false, enabled: true) == .transcribing)
        #expect(HUDPresenter.content(phase: .injecting, justCompleted: false, enabled: true) == .transcribing)
    }

    @Test func idleWithJustCompletedShowsDone() {
        #expect(HUDPresenter.content(phase: .idle, justCompleted: true, enabled: true) == .done)
    }

    @Test func idleWithoutCompletionHidden() {
        // 不常驻:idle 且无刚完成 → 隐藏
        #expect(HUDPresenter.content(phase: .idle, justCompleted: false, enabled: true) == .hidden)
    }

    @Test func errorHidden() {
        #expect(HUDPresenter.content(phase: .error, justCompleted: false, enabled: true) == .hidden)
    }

    @Test func disabledAlwaysHidden() {
        // 开关关掉 → 任何状态都隐藏
        for phase in [HUDPhase.recording, .transcribing, .injecting, .idle, .error] {
            #expect(HUDPresenter.content(phase: phase, justCompleted: true, enabled: false) == .hidden)
        }
    }

    @Test func visibilityFlag() {
        #expect(HUDContent.recording.isVisible)
        #expect(HUDContent.transcribing.isVisible)
        #expect(HUDContent.done.isVisible)
        #expect(!HUDContent.hidden.isVisible)
    }

    @Test func levelNormalization() {
        #expect(HUDPresenter.normalizedLevel(db: -60) == 0)
        #expect(HUDPresenter.normalizedLevel(db: 0) == 1)
        #expect(HUDPresenter.normalizedLevel(db: -30) == 0.5)
        #expect(HUDPresenter.normalizedLevel(db: -120) == 0) // 下限截断
        #expect(HUDPresenter.normalizedLevel(db: 20) == 1)   // 上限截断
    }
}
