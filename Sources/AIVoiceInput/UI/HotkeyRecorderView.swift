import AIVoiceInputCore
import AppKit
import SwiftUI

/// 快捷键录制控件:NSViewRepresentable 捕获 keyDown(PLAN §5.1)。
/// 点击进入录制态 → 下一个带修饰键的按键组合被捕获 → 回调。
struct HotkeyRecorderView: NSViewRepresentable {
    let hotkey: Hotkey
    let prompt: String
    let onRecorded: (Hotkey) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecorded = onRecorded
        button.recordingPrompt = prompt
        button.update(hotkey: hotkey)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onRecorded = onRecorded
        nsView.recordingPrompt = prompt
        if !nsView.isRecording { nsView.update(hotkey: hotkey) }
    }
}

final class RecorderButton: NSButton {
    var onRecorded: ((Hotkey) -> Void)?
    var recordingPrompt = "Press keys…"
    private(set) var isRecording = false
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(hotkey: Hotkey) {
        title = hotkey.displayString
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = recordingPrompt
        // 本地 monitor:录制窗聚焦时截获 keyDown/flagsChanged
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape:取消录制
                self.stopRecording()
                return nil
            }
            let hotkey = Hotkey(event: event)
            self.stopRecording()
            self.onRecorded?(hotkey)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
