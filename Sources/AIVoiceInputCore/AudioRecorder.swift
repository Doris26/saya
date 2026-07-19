import AVFoundation

/// AVAudioRecorder 封装:16kHz 单声道 AAC 32kbps 临时文件(实测 0.247 MB/min,FINDINGS §6)。
/// 5 分钟硬上限防口袋误触烧钱(PLAN §2.3),经 record(forDuration:) + delegate 回调。
@MainActor
public final class AudioRecorder: NSObject {
    public enum RecorderError: LocalizedError {
        case noInputDevice
        case startFailed

        public var errorDescription: String? {
            switch self {
            case .noInputDevice: "没有可用的音频输入设备"
            case .startFailed: "录音启动失败"
            }
        }
    }

    public static let maxDuration: TimeInterval = 300

    private var recorder: AVAudioRecorder?
    public private(set) var currentFileURL: URL?

    /// 5 分钟硬上限自动停止时回调(手动 stop 不触发)
    public var onAutoStop: (@MainActor (URL) -> Void)?

    public var isRecording: Bool { recorder?.isRecording ?? false }
    public var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    public func start() throws {
        // 录音前检查输入设备存在(AirPods 切换瞬间可能无输入,PLAN §2.3)
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw RecorderError.noInputDevice
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-voice-input", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970)).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.delegate = self
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record(forDuration: Self.maxDuration) else {
            throw RecorderError.startFailed
        }
        recorder = newRecorder
        currentFileURL = url
        Log.audio.info("recording started -> \(url.lastPathComponent, privacy: .public)")
    }

    /// 手动停止;返回录音文件 URL
    public func stop() -> URL? {
        guard let activeRecorder = recorder, let url = currentFileURL else { return nil }
        recorder = nil // 先清引用:delegate 回调据此区分手动停 vs 5min 自动停
        activeRecorder.stop()
        Log.audio.info("recording stopped, duration logged at stop")
        return url
    }

    /// 当前电平 dBFS(录音中才有值;实测 idle ≈ −48,说话 ≈ −17,FINDINGS §6)
    public func averagePowerDB() -> Float? {
        guard let activeRecorder = recorder, activeRecorder.isRecording else { return nil }
        activeRecorder.updateMeters()
        return activeRecorder.averagePower(forChannel: 0)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ finishedRecorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            // 手动 stop() 已把 self.recorder 置 nil → 这里只处理 5min 硬上限自动停
            guard self.recorder === finishedRecorder, let url = self.currentFileURL else { return }
            self.recorder = nil
            Log.audio.info("auto-stopped at 5min cap (success=\(flag, privacy: .public))")
            self.onAutoStop?(url)
        }
    }
}
