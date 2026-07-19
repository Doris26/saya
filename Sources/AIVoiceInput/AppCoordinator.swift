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
}

/// 唯一状态机与编排者。M1:热键 toggle 真录音;M2 起接转写。
@MainActor
@Observable
final class AppCoordinator {
    private(set) var state: AppState = .idle
    private(set) var hotkeyFireCount = 0
    private(set) var levelDB: Float?
    private(set) var recordingSeconds = 0
    private(set) var lastRecordingURL: URL?
    let hotkey: Hotkey = .defaultToggle

    @ObservationIgnored private let hotkeyManager = HotkeyManager()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let permissions = PermissionManager()
    /// 防重入:mic 授权 dialog await 期间再按热键不得再起一个 startRecording(实测竞态)
    @ObservationIgnored private var isStartingRecording = false

    var statusLine: String {
        switch state {
        case .idle:
            return "空闲"
        case .recording:
            let level = levelDB.map { String(format: " · %.0f dB", $0) } ?? ""
            return "录音中… \(recordingSeconds / 60):\(String(format: "%02d", recordingSeconds % 60))\(level)"
        case .transcribing:
            return "转写中…"
        case .error(let message):
            return "错误:\(message)"
        }
    }

    init() {
        registerHotkey()
        recorder.onAutoStop = { [weak self] url in
            self?.finishRecording(with: url, reason: "5min cap")
        }
    }

    func toggleRecording() {
        switch state {
        case .idle, .error:
            guard !isStartingRecording else {
                Log.app.info("toggle ignored: start already in flight (permission dialog?)")
                return
            }
            isStartingRecording = true
            Task {
                await startRecording()
                isStartingRecording = false
            }
        case .recording:
            if let url = recorder.stop() {
                finishRecording(with: url, reason: "manual stop")
            } else {
                state = .idle
            }
        case .transcribing:
            // 转写期间 toggle 无操作;M2 起决定是否允许排队/取消
            Log.app.info("toggle ignored while transcribing")
        }
    }

    func revealLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Recording

    private func startRecording() async {
        switch permissions.micPermission {
        case .denied:
            state = .error("麦克风权限被拒绝——请在 系统设置→隐私与安全性→麦克风 打开")
            permissions.openMicrophoneSettings()
            return
        case .undetermined:
            guard await permissions.requestMicAccess() else {
                // 弹窗被拒(或非 GUI 环境弹不出,FINDINGS §6)
                state = .error("未获得麦克风权限")
                return
            }
        case .granted:
            break
        }

        do {
            try recorder.start()
            state = .recording
            startMeterLoop()
        } catch {
            state = .error(error.localizedDescription)
            Log.audio.error("start failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func finishRecording(with url: URL, reason: String) {
        levelDB = nil
        recordingSeconds = 0
        lastRecordingURL = url
        // M1: 停在 idle,文件留验收;M2 起 -> .transcribing -> TranscriptionClient
        state = .idle
        Log.app.info("recorded (\(reason, privacy: .public)) -> \(url.path, privacy: .public)")
    }

    /// 录音期间 5Hz 刷电平 + 秒数(数据源实测可用,FINDINGS §6)
    private func startMeterLoop() {
        Task { [weak self] in
            while let self, self.state == .recording {
                self.levelDB = self.recorder.averagePowerDB()
                self.recordingSeconds = Int(self.recorder.currentTime)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: - Hotkey

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
