import AIVoiceInputCore
import AppKit
import Observation

/// App 全局状态(与 PLAN §1.1 图对齐,grill #8:injecting 补入,M3 启用)。
enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case injecting
    case error(String)

    var menuBarSymbol: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing, .injecting: "waveform"
        case .error: "mic.slash"
        }
    }
}

/// 唯一状态机与编排者。M2:录音→转写→菜单可找回;注入是 M3。
/// 热键转移表(PLAN §1.2):idle/error→开录;recording→停录进管线;transcribing/injecting→忽略+日志。
@MainActor
@Observable
final class AppCoordinator {
    private(set) var state: AppState = .idle
    private(set) var hotkeyFireCount = 0
    private(set) var levelDB: Float?
    private(set) var recordingSeconds = 0
    /// 【P0#1】注入成功不可探测 → 内存保留最近一次转写,菜单可复制(唯一找回路径)
    private(set) var lastTranscript: String?
    private(set) var lastNote: String?
    private(set) var failedRecordingURL: URL?
    /// 触发失败提示(fn 模式 CGEventTap 挂载失败=辅助功能未授权)
    private(set) var triggerNote: String?
    let settings: SettingsStore
    var hotkey: Hotkey { settings.hotkey }

    /// 菜单/状态展示用的触发方式描述
    var triggerDisplay: String {
        switch settings.triggerMode {
        case .fnKey: "🌐 fn 单键"
        case .combo: settings.hotkey.displayString
        }
    }

    @ObservationIgnored private let hotkeyManager = HotkeyManager()
    @ObservationIgnored private let fnMonitor = FnKeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let permissions = PermissionManager()
    @ObservationIgnored private let transcriber = TranscriptionClient()
    @ObservationIgnored private let injector = TextInjector()
    /// 停录瞬间(用户按热键=意图锚点)的焦点快照,注入前 recheck(grill #6)
    @ObservationIgnored private var pendingFocus: FocusSnapshot?
    /// 防重入:mic 授权 dialog await 期间再按热键不得再起一个 startRecording(实测竞态)
    @ObservationIgnored private var isStartingRecording = false
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    /// 录音全程最大电平(静音 gate 数据源,grill #5)
    @ObservationIgnored private var maxLevelDB: Float = -160
    @ObservationIgnored private var recordingDuration: TimeInterval = 0
    /// 【P0#1】音频延迟到下次录音开始才删(始终留一次重试机会)
    @ObservationIgnored private var pendingDeletionURL: URL?

    /// grill #5:三层静音/误触 gate 的阈值。本底实测 −48 dBFS、正常语音 −17(FINDINGS §6);
    /// 阈值保守取 −42——宁可放过静音也不吞真口述(误杀=P0#1 级伤害)
    static let minDuration: TimeInterval = 0.7
    static let speechLevelFloorDB: Float = -42

    var statusLine: String {
        switch state {
        case .idle:
            return "空闲"
        case .recording:
            let level = levelDB.map { String(format: " · %.0f dB", $0) } ?? ""
            return "录音中… \(recordingSeconds / 60):\(String(format: "%02d", recordingSeconds % 60))\(level)"
        case .transcribing:
            return "转写中…"
        case .injecting:
            return "输入中…"
        case .error(let message):
            return "错误:\(message)"
        }
    }

    @ObservationIgnored private var debugSignalSource: DispatchSourceSignal?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        setupTrigger()
        recorder.onAutoStop = { [weak self] url in
            // grill #5:5min cap 的自动停止走完整转写但永不自动注入(M3 起也一样)
            self?.handleRecordingFinished(url: url, autoStopped: true)
        }
        sweepStaleAudio()
        installDebugSignalHook()
    }

    /// grill #14:内存验收改造——SIGUSR1 触发 toggleRecording,供 bin/leak_harness.sh
    /// headless 驱动 50 次录/转/注循环(本机无 Instruments,已实测;footprint/leaks 采样)。
    /// 仅 AIVI_DEBUG_DIR 设置时挂,生产不装。
    private func installDebugSignalHook() {
        guard ProcessInfo.processInfo.environment["AIVI_DEBUG_DIR"] != nil else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.toggleRecording() }
        source.resume()
        debugSignalSource = source
        Log.app.info("debug SIGUSR1 hook installed")
    }

    /// 设置里改了热键或触发模式 → 立即重挂(PLAN §2.1:先注销再注册)
    func applyHotkeyChange() {
        setupTrigger()
    }

    /// 「测试连接」:用当前 key 打一发轻量请求,回报结果
    func testAPIKey() async -> String {
        let key = settings.effectiveAPIKey
        guard !key.isEmpty else { return "未配置 API Key" }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "无响应" }
            switch http.statusCode {
            case 200: return "连接成功 ✓"
            case 401: return "Key 无效(401)"
            default: return "HTTP \(http.statusCode)"
            }
        } catch {
            return "网络错误:\(error.localizedDescription)"
        }
    }

    // MARK: - 热键转移表

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
            pendingFocus = injector.captureFocus() // 意图锚点:此刻的光标位置才是注入目标
            recordingDuration = recorder.currentTime
            if let url = recorder.stop() {
                handleRecordingFinished(url: url, autoStopped: false)
            } else {
                state = .idle
            }
        case .transcribing, .injecting:
            Log.app.info("toggle ignored in state \(String(describing: self.state), privacy: .public)")
        }
    }

    /// grill #7:取消——recording 态丢音频,transcribing 态丢结果;零 API 零注入
    func cancel() {
        switch state {
        case .recording:
            recordingDuration = 0
            if let url = recorder.stop() {
                try? FileManager.default.removeItem(at: url)
            }
            leaveRecordingState()
            state = .idle
            lastNote = "已取消录音(音频已丢弃)"
            playSound("Basso")
            Log.app.info("recording cancelled")
        case .transcribing:
            transcribeTask?.cancel()
        default:
            break
        }
    }

    func retryTranscription() {
        guard state != .recording, state != .transcribing, let url = failedRecordingURL else { return }
        transcribe(url: url, autoStopped: false)
    }

    func copyLastTranscript() {
        guard let text = lastTranscript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastNote = "已复制到剪贴板"
    }

    func revealLastRecording() {
        let url = failedRecordingURL ?? pendingDeletionURL
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
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
                state = .error("未获得麦克风权限")
                return
            }
        case .granted:
            break
        }

        // 【P0#1】上一条音频到此刻(新录音开始)才删
        if let url = pendingDeletionURL {
            try? FileManager.default.removeItem(at: url)
            pendingDeletionURL = nil
        }
        if let url = failedRecordingURL {
            // 单槽策略(grill #26):新录音覆盖失败槽
            try? FileManager.default.removeItem(at: url)
            failedRecordingURL = nil
        }

        do {
            try recorder.start()
            maxLevelDB = -160
            lastNote = nil
            state = .recording
            playSound("Pop") // grill #9:开始提示音(全屏/notch 下唯一反馈)
            // grill #7:仅录音期间临时注册 Esc 取消(tradeoff:此间系统级占用 Esc)
            try? hotkeyManager.registerCancelKey { [weak self] in self?.cancel() }
            startMeterLoop()
        } catch {
            state = .error(error.localizedDescription)
            Log.audio.error("start failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func leaveRecordingState() {
        hotkeyManager.unregisterCancelKey()
        levelDB = nil
        recordingSeconds = 0
    }

    private func handleRecordingFinished(url: URL, autoStopped: Bool) {
        if autoStopped { recordingDuration = AudioRecorder.maxDuration }
        leaveRecordingState()
        playSound("Glass") // grill #9:结束提示音

        // grill #5 gate 1:<0.7s 丢弃不调 API(误触)
        guard recordingDuration >= Self.minDuration else {
            try? FileManager.default.removeItem(at: url)
            state = .idle
            lastNote = "录音过短(<0.7s)已丢弃"
            Log.app.info("discarded: too short (\(self.recordingDuration, privacy: .public)s)")
            return
        }
        // grill #5 gate 2:电平全程未过噪声底 → 跳过 API(静音幻觉防线;文件保留可手动重试)
        guard maxLevelDB >= Self.speechLevelFloorDB else {
            failedRecordingURL = url
            state = .idle
            lastNote = String(format: "未检测到语音(峰值 %.0f dB)已跳过转写,可从菜单重试", maxLevelDB)
            Log.app.info("skipped API: max level \(self.maxLevelDB, privacy: .public) below floor")
            return
        }
        if autoStopped { lastNote = "已达 5 分钟上限自动停止" }
        transcribe(url: url, autoStopped: autoStopped)
    }

    /// 录音期间 5Hz 刷电平/秒数/最大电平(menu-tracking-safe:Task 非 default-mode Timer,grill #17)
    private func startMeterLoop() {
        Task { [weak self] in
            while let self, self.state == .recording {
                if let level = self.recorder.averagePowerDB() {
                    self.levelDB = level
                    self.maxLevelDB = max(self.maxLevelDB, level)
                }
                self.recordingSeconds = Int(self.recorder.currentTime)
                self.recordingDuration = self.recorder.currentTime
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: - Transcription (M2)

    private func transcribe(url: URL, autoStopped: Bool) {
        // Keychain 优先,dev 期回落 env(release 忽略,grill #29)——统一走 SettingsStore
        let apiKey = settings.effectiveAPIKey
        guard !apiKey.isEmpty else {
            failedRecordingURL = url
            state = .error("未配置 API Key——请在 设置 里填写")
            lastNote = "未配置 API Key(音频已保留,填 Key 后可重试)"
            playSound("Basso")
            return
        }
        state = .transcribing
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let started = Date()
                let result = try await self.transcriber.transcribe(
                    fileURL: url, apiKey: apiKey,
                    model: self.settings.model,
                    prompt: self.buildPrompt()
                )
                let elapsed = Date().timeIntervalSince(started)
                // M5:去口头禅本地后处理(保守,默认关;prompt 是第一层)
                let text = self.settings.removeFillers
                    ? TextPostProcessor.removeFillers(result.text) : result.text
                self.lastTranscript = text
                self.failedRecordingURL = nil
                self.pendingDeletionURL = url // 【P0#1】不立即删,下次录音开始才删
                self.lastNote = String(
                    format: "转写完成(%d 字 · %.1fs%@)",
                    text.count, elapsed,
                    result.totalTokens.map { " · \($0) tok" } ?? ""
                )
                // M3:注入。5min-cap 自动停永不注入(grill #5,无人值守链禁止)
                if autoStopped {
                    self.state = .idle
                    self.lastNote = "已达 5 分钟上限自动停止——文本在菜单「复制上次转写」"
                } else {
                    await self.injectTranscript(text)
                }
                // 隐私(grill #27):transcript 正文不 .public
                Log.transcribe.info("ok: \(text.count, privacy: .public) chars in \(elapsed, privacy: .public)s")
                // agent 验收通道(dev only):AIVI_DEBUG_DIR 设置时落 transcript 到 0600 文件,
                // 不经 unified log(unified log 里正文保持 private)
                if let debugDir = ProcessInfo.processInfo.environment["AIVI_DEBUG_DIR"] {
                    let debugFile = URL(fileURLWithPath: debugDir).appendingPathComponent("last_transcript.txt")
                    try? text.write(to: debugFile, atomically: true, encoding: .utf8)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: debugFile.path)
                }
            } catch is CancellationError {
                self.handleTranscribeFailure(url: url, note: "已取消转写(音频保留,可重试)")
            } catch let error as TranscriptionClient.TranscriptionError {
                self.handleTranscribeFailure(url: url, note: error.localizedDescription)
            } catch {
                let urlError = error as? URLError
                if urlError?.code == .cancelled {
                    self.handleTranscribeFailure(url: url, note: "已取消转写(音频保留,可重试)")
                } else {
                    self.handleTranscribeFailure(url: url, note: error.localizedDescription)
                }
            }
            self.transcribeTask = nil
        }
    }

    /// 强制简体是硬性(简繁非确定性,FINDINGS);标点/去口头禅按设置拼(prompt 保持短,计费,grill）
    private func buildPrompt() -> String {
        var parts = ["中文使用简体中文输出。"]
        if settings.autoPunctuation { parts.append("请输出带标点的书面文本。Punctuate properly.") }
        if settings.removeFillers { parts.append("去除嗯呃等口头禅。Remove filler words.") }
        return parts.joined()
    }

    // MARK: - Injection (M3)

    private func injectTranscript(_ text: String) async {
        state = .injecting
        defer { pendingFocus = nil }
        let method = TextInjector.Method(rawValue: settings.injectionMethod) ?? .auto
        do {
            let outcome = try await injector.inject(text, method: method, expectedFocus: pendingFocus)
            state = .idle
            switch outcome {
            case .attempted(let method):
                // 粘贴成功不可探测(P0#1)——语义是「已尝试」,找回路径常驻菜单
                lastNote = "已输入(\(method == .paste ? "粘贴" : "打字")法)· 找回:菜单「复制上次转写」"
                Log.inject.info("attempted via \(method.rawValue, privacy: .public)")
            case .refusedSecureContext(let culprit):
                // P0#2:secure 拒注不落剪贴板,文本只留菜单
                lastNote = "检测到安全输入\(culprit.map { "(\($0))" } ?? "")已拒绝注入——文本在菜单"
                playSound("Basso")
            case .fellBackToClipboard(let reason):
                lastNote = "\(reason)——文本已复制到剪贴板"
                playSound("Basso")
            }
        } catch is TextInjector.InjectorError {
            state = .idle
            lastNote = "辅助功能未授权——文本在菜单;请在 系统设置→隐私与安全性→辅助功能 打开"
            playSound("Basso")
            // 首次触发系统提示 + 直达设置(PLAN §2.4)
            // kAXTrustedCheckOptionPrompt 是 C 全局 var,Swift 6 判定非并发安全 → 用其原始字符串值
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            permissions.openAccessibilitySettings()
        } catch {
            state = .idle
            lastNote = "注入异常:\(error.localizedDescription)——文本在菜单"
            playSound("Basso")
        }
    }

    private func handleTranscribeFailure(url: URL, note: String) {
        failedRecordingURL = url // 音频保留,菜单可重试(PLAN §7#3)
        state = .error(note)
        lastNote = note
        playSound("Basso")
        Log.transcribe.error("failed: \(note, privacy: .public)")
    }

    // MARK: - Housekeeping

    /// grill #26:启动清扫 >24h 残留音频;目录收紧 0700
    private func sweepStaleAudio() {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("ai-voice-input", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? fileManager.removeItem(at: file)
                    Log.app.info("swept stale audio \(file.lastPathComponent, privacy: .public)")
                }
            }
        }
    }

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Hotkey

    /// 按 triggerMode 挂载触发器:fn 模式=CGEventTap 边沿检测,combo 模式=Carbon 热键。
    private func setupTrigger() {
        // 先全部注销,避免两个触发器同时活着
        hotkeyManager.unregisterAll()
        fnMonitor.stop()
        triggerNote = nil

        let onFire: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            hotkeyFireCount += 1
            Log.hotkey.info("trigger fired count=\(self.hotkeyFireCount, privacy: .public)")
            toggleRecording()
        }

        switch settings.triggerMode {
        case .fnKey:
            if fnMonitor.start(onTap: onFire) {
                if case .error = state { state = .idle }
                Log.hotkey.info("trigger=fn key")
            } else {
                // CGEventTap 挂载失败 = 辅助功能未授权
                triggerNote = "fn 监听需要辅助功能授权——请在 系统设置→隐私与安全性→辅助功能 打开"
                Log.hotkey.error("fn monitor failed to start (accessibility not granted?)")
            }
        case .combo:
            do {
                try hotkeyManager.register(settings.hotkey, handler: onFire)
                if case .error = state { state = .idle }
                Log.hotkey.info("trigger=combo \(self.settings.hotkey.displayString, privacy: .public)")
            } catch {
                // -9868 = macOS 15+ 拒绝 option-only 组合(grill #10)
                state = .error("热键注册失败(\(settings.hotkey.displayString) 可能被占用)")
                Log.hotkey.error("register failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
