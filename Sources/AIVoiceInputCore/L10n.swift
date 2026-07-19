import Foundation

/// 界面语言偏好(持久化在 SettingsStore)。
public enum AppLanguage: String, CaseIterable, Sendable {
    case system  // 跟随系统 Locale
    case zh
    case en
}

/// 解析后的实际语言(只有两套翻译)。
public enum ResolvedLanguage: Sendable {
    case zh
    case en
}

/// 所有面向用户的字串 key。用穷举 switch 提供翻译 → 编译期保证每个 key 都有 zh/en 两套(无遗漏)。
public enum LocKey: String, CaseIterable, Sendable {
    // 菜单
    case menuTriggerLine, menuStop, menuCancelRecording, menuCancelTranscribe, menuStart
    case menuRecentTranscript, menuCopyLast, menuRetry, menuRevealAudio
    case menuUsageMonth, menuUsageToday, menuSettings, menuQuit
    // 状态行
    case statusIdle, statusRecording, statusTranscribing, statusInjecting, statusError
    case triggerFnKey
    // 提示 note
    case noteCancelled, noteTooShort, noteNoSpeech, noteAutoStopCap, noteNoKey
    case noteTranscribed, noteTranscribedTokens, noteInserted, noteRefusedSecure, noteFellBack
    case noteAXDenied, noteInjectError, noteCopied, noteCancelledTranscribe
    case methodPaste, methodType, reasonFocusChanged
    // 错误
    case errMicDenied, errMicNotGranted, errNoKeySettings, errHotkeyRegister, triggerNoteFnAX
    // 测试连接
    case testNoKey, testOK, testBadKey, testHTTP, testNetErr, testNoResp
    // 设置窗
    case tabGeneral, tabShortcut, tabAdvanced
    case secAPIKey, apiKeyPlaceholderHas, apiKeyPlaceholderEmpty, btnSave, savedMasked
    case labelSaved, labelNotConfigured, btnTest, btnTesting
    case secInjection, injAuto, injPaste, injType
    case toggleLaunch, toggleHUD
    case secUsage, usageMonth, usageToday, usageMonthValue, usageTodayValue, usageNote
    case secTrigger, trigFn, trigCombo, fnHint1, fnHint2, secCombo, comboHint, escHint
    case secTranscribe, modelLabel, modelQuality, modelCheap
    case secPost, togglePunct, toggleFillers, fillersHint
    case secLanguage, langLabel, langSystem, langZh, langEn
    case recorderPrompt
    // HUD
    case hudRecording, hudTranscribing, hudDone
    // Onboarding
    case obWelcomeTitle, obWelcomeBody, obStart
    case obMicTitle, obMicBodyGranted, obMicBody, obNext, obGrantMic
    case obAXTitle, obAXBodyGranted, obAXBody, obOpenSettings
    case obNotifTitle, obNotifBody, obAllowNotif
    case obTriggerTitle, obTriggerBody, obOpenKeyboard
    case obKeyTitle, obSaveFinish, obLater
    // Core 错误
    case errNoInputDevice, errStartFailed
    case terrNoKey, terrTooLarge, terrInvalidKey, terrRateLimited, terrTimeout
    case terrNetwork, terrServer, terrEmpty, terrGeneric
    case valModifierOnly, valOptionOnly, valNoModifier
}

/// 取词器。构造时定好语言,之后 `l10n.t(.key)` 取词、`l10n.t(.key, args)` 带格式。
public struct L10n: Sendable {
    public let lang: ResolvedLanguage

    public init(_ preference: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        switch preference {
        case .zh: lang = .zh
        case .en: lang = .en
        case .system:
            let first = preferredLanguages.first?.lowercased() ?? "en"
            lang = first.hasPrefix("zh") ? .zh : .en
        }
    }

    public func t(_ key: LocKey) -> String {
        let s = Self.table(key)
        return lang == .zh ? s.zh : s.en
    }

    public func t(_ key: LocKey, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// (zh, en) 供覆盖率测试用
    public static func pair(_ key: LocKey) -> (zh: String, en: String) {
        let s = Self.table(key); return (s.zh, s.en)
    }

    private struct S { let zh: String; let en: String }

    // 穷举 switch:编译期强制每个 LocKey 都有 zh/en 翻译。printf 说明符在 zh/en 里顺序一致。
    private static func table(_ key: LocKey) -> S {
        switch key {
        // 菜单
        case .menuTriggerLine: return S(zh: "触发 %@ · 已触发 %d 次", en: "Trigger %@ · fired %d×")
        case .menuStop: return S(zh: "停止录音", en: "Stop recording")
        case .menuCancelRecording: return S(zh: "取消录音(Esc)", en: "Cancel (Esc)")
        case .menuCancelTranscribe: return S(zh: "取消转写", en: "Cancel transcribing")
        case .menuStart: return S(zh: "开始录音", en: "Start recording")
        case .menuRecentTranscript: return S(zh: "最近转写:%@", en: "Last: %@")
        case .menuCopyLast: return S(zh: "复制上次转写", en: "Copy last transcript")
        case .menuRetry: return S(zh: "重试转写", en: "Retry transcription")
        case .menuRevealAudio: return S(zh: "在访达中显示保留音频", en: "Show saved audio in Finder")
        // 用量格式:zh/en 参数个数不同 → 用位置说明符 %1$/%2$/%3$(minutes, cny, usd),各取所需
        case .menuUsageMonth: return S(zh: "本月 %1$.0f 分钟 · ¥%2$.2f($%3$.3f)", en: "This month: %1$.0f min · $%3$.3f")
        case .menuUsageToday: return S(zh: "今日 %1$.0f 分钟 · ¥%2$.2f", en: "Today: %1$.0f min · $%3$.3f")
        case .menuSettings: return S(zh: "设置…", en: "Settings…")
        case .menuQuit: return S(zh: "退出 Saya", en: "Quit Saya")
        // 状态行
        case .statusIdle: return S(zh: "空闲", en: "Idle")
        case .statusRecording: return S(zh: "录音中… %@", en: "Recording… %@")
        case .statusTranscribing: return S(zh: "转写中…", en: "Transcribing…")
        case .statusInjecting: return S(zh: "输入中…", en: "Inserting…")
        case .statusError: return S(zh: "错误:%@", en: "Error: %@")
        case .triggerFnKey: return S(zh: "🌐 fn 单键", en: "🌐 fn key")
        // note
        case .noteCancelled: return S(zh: "已取消录音(音频已丢弃)", en: "Recording cancelled (audio discarded)")
        case .noteTooShort: return S(zh: "录音过短(<0.7s)已丢弃", en: "Too short (<0.7s), discarded")
        case .noteNoSpeech: return S(zh: "未检测到语音(峰值 %.0f dB)已跳过,可从菜单重试", en: "No speech (peak %.0f dB), skipped; retry from menu")
        case .noteAutoStopCap: return S(zh: "已达 5 分钟上限自动停止——文本在菜单「复制上次转写」", en: "Stopped at 5-min limit — text in menu → Copy last transcript")
        case .noteNoKey: return S(zh: "未配置 API Key(音频已保留,填 Key 后可重试)", en: "No API key (audio kept; add key and retry)")
        case .noteTranscribed: return S(zh: "转写完成(%d 字 · %.1fs)", en: "Transcribed (%d chars · %.1fs)")
        case .noteTranscribedTokens: return S(zh: "转写完成(%d 字 · %.1fs · %d tok)", en: "Transcribed (%d chars · %.1fs · %d tok)")
        case .noteInserted: return S(zh: "已输入(%@)· 找回:菜单「复制上次转写」", en: "Inserted (%@) · recover: menu → Copy last transcript")
        case .noteRefusedSecure: return S(zh: "检测到安全输入%@已拒绝注入——文本在菜单", en: "Secure input%@ detected; injection refused — text in menu")
        case .noteFellBack: return S(zh: "%@——文本已复制到剪贴板", en: "%@ — text copied to clipboard")
        case .noteAXDenied: return S(zh: "辅助功能未授权——文本在菜单;请在 系统设置→隐私与安全性→辅助功能 打开", en: "Accessibility not granted — text in menu; enable in System Settings → Privacy & Security → Accessibility")
        case .noteInjectError: return S(zh: "注入异常:%@——文本在菜单", en: "Insertion error: %@ — text in menu")
        case .noteCopied: return S(zh: "已复制到剪贴板", en: "Copied to clipboard")
        case .noteCancelledTranscribe: return S(zh: "已取消转写(音频保留,可重试)", en: "Transcription cancelled (audio kept; retry)")
        case .methodPaste: return S(zh: "粘贴法", en: "paste")
        case .methodType: return S(zh: "打字法", en: "type")
        case .reasonFocusChanged: return S(zh: "目标窗口/输入框已变化", en: "Target window/field changed")
        // 错误
        case .errMicDenied: return S(zh: "麦克风权限被拒绝——请在 系统设置→隐私与安全性→麦克风 打开", en: "Microphone denied — enable in System Settings → Privacy & Security → Microphone")
        case .errMicNotGranted: return S(zh: "未获得麦克风权限", en: "Microphone permission not granted")
        case .errNoKeySettings: return S(zh: "未配置 API Key——请在 设置 里填写", en: "No API key — set it in Settings")
        case .errHotkeyRegister: return S(zh: "热键注册失败(%@ 可能被占用)", en: "Shortcut registration failed (%@ may be in use)")
        case .triggerNoteFnAX: return S(zh: "fn 监听需要辅助功能授权——请在 系统设置→隐私与安全性→辅助功能 打开", en: "fn monitoring needs Accessibility — enable in System Settings → Privacy & Security → Accessibility")
        // 测试连接
        case .testNoKey: return S(zh: "未配置 API Key", en: "No API key set")
        case .testOK: return S(zh: "连接成功 ✓", en: "Connected ✓")
        case .testBadKey: return S(zh: "Key 无效(401)", en: "Invalid key (401)")
        case .testHTTP: return S(zh: "HTTP %d", en: "HTTP %d")
        case .testNetErr: return S(zh: "网络错误:%@", en: "Network error: %@")
        case .testNoResp: return S(zh: "无响应", en: "No response")
        // 设置窗
        case .tabGeneral: return S(zh: "通用", en: "General")
        case .tabShortcut: return S(zh: "快捷键", en: "Shortcut")
        case .tabAdvanced: return S(zh: "高级", en: "Advanced")
        case .secAPIKey: return S(zh: "OpenAI API Key", en: "OpenAI API Key")
        case .apiKeyPlaceholderHas: return S(zh: "粘贴新 Key 可更换(留空保留当前)", en: "Paste a new key to replace (blank keeps current)")
        case .apiKeyPlaceholderEmpty: return S(zh: "sk-…", en: "sk-…")
        case .btnSave: return S(zh: "保存", en: "Save")
        case .savedMasked: return S(zh: "已保存 ✓(%@)", en: "Saved ✓ (%@)")
        case .labelSaved: return S(zh: "已保存:%@", en: "Saved: %@")
        case .labelNotConfigured: return S(zh: "未配置", en: "Not set")
        case .btnTest: return S(zh: "测试连接", en: "Test connection")
        case .btnTesting: return S(zh: "测试中…", en: "Testing…")
        case .secInjection: return S(zh: "注入方式", en: "Insertion method")
        case .injAuto: return S(zh: "自动(粘贴优先)", en: "Automatic (paste first)")
        case .injPaste: return S(zh: "剪贴板 + ⌘V", en: "Clipboard + ⌘V")
        case .injType: return S(zh: "模拟打字", en: "Simulated typing")
        case .toggleLaunch: return S(zh: "开机自动启动", en: "Launch at login")
        case .toggleHUD: return S(zh: "显示录音浮层(屏幕底部)", en: "Show recording overlay (bottom of screen)")
        case .secUsage: return S(zh: "用量 / 花费", en: "Usage / Cost")
        case .usageMonth: return S(zh: "本月", en: "This month")
        case .usageToday: return S(zh: "今日", en: "Today")
        case .usageMonthValue: return S(zh: "%1$.0f 分钟 · ¥%2$.2f($%3$.3f)", en: "%1$.0f min · $%3$.3f")
        case .usageTodayValue: return S(zh: "%1$.0f 分钟 · ¥%2$.2f", en: "%1$.0f min · $%3$.3f")
        case .usageNote: return S(zh: "按音频时长 × 分钟价记账(gpt-4o-transcribe $0.006/min、mini $0.003/min);¥ 按约 7.2 汇率展示。记录存 ~/Library/Application Support/Saya/usage.jsonl。", en: "Billed by audio duration × per-minute rate (gpt-4o-transcribe $0.006/min, mini $0.003/min). Records stored at ~/Library/Application Support/Saya/usage.jsonl.")
        case .secTrigger: return S(zh: "触发方式", en: "Trigger")
        case .trigFn: return S(zh: "🌐 fn 单键 toggle", en: "🌐 fn key toggle")
        case .trigCombo: return S(zh: "自定义组合键", en: "Custom shortcut")
        case .fnHint1: return S(zh: "按一下 🌐 fn(地球键)开始录音,再按一下停止。", en: "Press 🌐 fn (Globe) once to start recording, again to stop.")
        case .fnHint2: return S(zh: "⚠️ macOS 默认单按 fn 会触发听写/emoji。请到 系统设置 → 键盘 →「按下 🌐 键用于」改为「无操作」,fn 单键 toggle 才不会和系统冲突。", en: "⚠️ macOS uses a single fn press for dictation/emoji by default. Go to System Settings → Keyboard → \"Press 🌐 key to\" and set it to \"Do Nothing\" so fn toggle won't conflict.")
        case .secCombo: return S(zh: "组合键", en: "Shortcut")
        case .comboHint: return S(zh: "按下想用的组合;须含 ⌃ 或 ⌘(系统不允许仅 ⌥/⇧ 的组合)。", en: "Press your combo; must include ⌃ or ⌘ (macOS forbids ⌥/⇧-only combos).")
        case .escHint: return S(zh: "录音时按 Esc 可取消(两种模式通用)。", en: "Press Esc while recording to cancel (both modes).")
        case .secTranscribe: return S(zh: "转写", en: "Transcription")
        case .modelLabel: return S(zh: "模型", en: "Model")
        case .modelQuality: return S(zh: "gpt-4o-transcribe(质量)", en: "gpt-4o-transcribe (quality)")
        case .modelCheap: return S(zh: "gpt-4o-mini-transcribe(省钱)", en: "gpt-4o-mini-transcribe (cheaper)")
        case .secPost: return S(zh: "后处理", en: "Post-processing")
        case .togglePunct: return S(zh: "自动补标点", en: "Auto punctuation")
        case .toggleFillers: return S(zh: "去除口头禅(嗯/呃/like…)", en: "Remove fillers (um/uh/like…)")
        case .fillersHint: return S(zh: "去口头禅较激进,可能误删内容;逐字场景建议关闭。", en: "Filler removal is aggressive and may drop real words; keep it off for verbatim.")
        case .secLanguage: return S(zh: "语言", en: "Language")
        case .langLabel: return S(zh: "界面语言", en: "Interface language")
        case .langSystem: return S(zh: "跟随系统", en: "System")
        case .langZh: return S(zh: "中文", en: "中文")
        case .langEn: return S(zh: "English", en: "English")
        case .recorderPrompt: return S(zh: "按下组合…(Esc 取消)", en: "Press keys… (Esc to cancel)")
        // HUD
        case .hudRecording: return S(zh: "正在听…", en: "Listening…")
        case .hudTranscribing: return S(zh: "转写中…", en: "Transcribing…")
        case .hudDone: return S(zh: "已输入", en: "Inserted")
        // Onboarding
        case .obWelcomeTitle: return S(zh: "欢迎使用 Saya", en: "Welcome to Saya")
        case .obWelcomeBody: return S(zh: "按全局热键说话,自动转写并输入到光标处。下面几步配置权限与 API Key。", en: "Press a global shortcut to speak; Saya transcribes and types it at your cursor. A few steps to set up permissions and your API key.")
        case .obStart: return S(zh: "开始", en: "Get started")
        case .obMicTitle: return S(zh: "麦克风权限", en: "Microphone")
        case .obMicBodyGranted: return S(zh: "已授权 ✓", en: "Granted ✓")
        case .obMicBody: return S(zh: "用于录制语音。点下面按钮授权。", en: "Needed to record your voice. Grant it below.")
        case .obNext: return S(zh: "下一步", en: "Next")
        case .obGrantMic: return S(zh: "授权麦克风", en: "Grant microphone")
        case .obAXTitle: return S(zh: "辅助功能权限", en: "Accessibility")
        case .obAXBodyGranted: return S(zh: "已授权 ✓", en: "Granted ✓")
        case .obAXBody: return S(zh: "用于把文字输入到当前 App。请在系统设置里打开开关(会自动检测)。", en: "Needed to type text into the current app. Turn it on in System Settings (auto-detected).")
        case .obOpenSettings: return S(zh: "打开系统设置", en: "Open System Settings")
        case .obNotifTitle: return S(zh: "通知权限", en: "Notifications")
        case .obNotifBody: return S(zh: "注入结果、设备切换等提示需要通知。", en: "Used for insertion results and device-change alerts.")
        case .obAllowNotif: return S(zh: "允许通知", en: "Allow notifications")
        case .obTriggerTitle: return S(zh: "触发方式:fn 单键", en: "Trigger: fn key")
        case .obTriggerBody: return S(zh: "默认按一下 🌐 fn(地球键)开始录音,再按一下停止。\n\n⚠️ macOS 默认单按 fn 是听写/emoji。请到 系统设置 → 键盘 →「按下 🌐 键用于」改为「无操作」,否则会和系统冲突。也可稍后在设置里改用组合键。", en: "By default, press 🌐 fn (Globe) once to start recording, again to stop.\n\n⚠️ macOS uses fn for dictation/emoji by default. Go to System Settings → Keyboard → \"Press 🌐 key to\" and set \"Do Nothing\", or switch to a custom shortcut later in Settings.")
        case .obOpenKeyboard: return S(zh: "打开键盘设置", en: "Open Keyboard Settings")
        case .obKeyTitle: return S(zh: "OpenAI API Key", en: "OpenAI API Key")
        case .obSaveFinish: return S(zh: "保存并完成", en: "Save & finish")
        case .obLater: return S(zh: "稍后设置", en: "Set up later")
        // Core 错误
        case .errNoInputDevice: return S(zh: "没有可用的音频输入设备", en: "No audio input device available")
        case .errStartFailed: return S(zh: "录音启动失败", en: "Failed to start recording")
        case .terrNoKey: return S(zh: "未配置 OpenAI API Key", en: "No OpenAI API key set")
        case .terrTooLarge: return S(zh: "录音文件过大(%d MB > 25 MB 上限)", en: "Audio file too large (%d MB > 25 MB limit)")
        case .terrInvalidKey: return S(zh: "API Key 无效(401)——请检查 Key", en: "Invalid API key (401) — check your key")
        case .terrRateLimited: return S(zh: "请求过于频繁(429)——稍后重试", en: "Rate limited (429) — try again shortly")
        case .terrTimeout: return S(zh: "转写超时(30s)——请检查网络", en: "Transcription timed out (30s) — check your network")
        case .terrNetwork: return S(zh: "网络错误:%@", en: "Network error: %@")
        case .terrServer: return S(zh: "服务端错误(%d):%@", en: "Server error (%d): %@")
        case .terrEmpty: return S(zh: "转写结果为空", en: "Empty transcript")
        case .terrGeneric: return S(zh: "转写失败", en: "Transcription failed")
        case .valModifierOnly: return S(zh: "请再按一个字母/数字键", en: "Press a letter/number key too")
        case .valOptionOnly: return S(zh: "系统不允许仅用 ⌥/⇧ 的组合,请加 ⌃ 或 ⌘", en: "macOS forbids ⌥/⇧-only combos; add ⌃ or ⌘")
        case .valNoModifier: return S(zh: "请至少加一个修饰键(⌃⌥⌘⇧)", en: "Add at least one modifier (⌃⌥⌘⇧)")
        }
    }
}
