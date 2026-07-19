# AI Voice Input — macOS 菜单栏语音输入 App 实施计划 (MVP)

> 版本: v1.0 | 日期: 2026-07-18 | 状态: PLAN
> 产品一句话: 全局快捷键按下开始录音、再按结束 → OpenAI `gpt-4o-transcribe` 转写 → 文字自动注入当前光标处。无 server、纯本地 App、只用苹果原生框架。

---

## 0. 范围与非目标

**MVP 范围**
- 菜单栏常驻 App(无 Dock 图标)
- 全局快捷键 toggle 录音(可配置)
- 录音 → 一次性上传 OpenAI Audio API 转写(中英混输)
- 转写结果注入当前前台 App 的光标处
- 设置窗口:API Key(Keychain)、快捷键、注入方式、自动标点/去口头禅开关
- Developer ID 签名 + 公证分发(非 App Store)

**非目标(MVP 不做)**
- 实时流式边说边出字(Realtime API websocket)— M5 之后再评估
- 本地离线模型(whisper.cpp / SpeechAnalyzer)
- 多语言 UI、自动更新(Sparkle 是第三方,违反"只用原生框架"约束,MVP 先手动分发)
- 历史记录/剪贴板历史

---

## 1. 架构

### 1.1 模块图

```
┌─────────────────────────────────────────────────────────────────┐
│                        AIVoiceInputApp (SwiftUI @main)          │
│                                                                 │
│  ┌──────────────┐        ┌───────────────────────────────────┐  │
│  │  MenuBarUI   │◀──────▶│        AppCoordinator             │  │
│  │ (MenuBarExtra│  状态   │  状态机: idle → recording →       │  │
│  │  + Settings  │  绑定   │  transcribing → injecting → idle  │  │
│  │  Window)     │        │  (@Observable, 唯一编排者)         │  │
│  └──────────────┘        └───┬───────┬────────┬───────┬──────┘  │
│                              │       │        │       │         │
│                    ┌─────────▼──┐ ┌──▼─────┐ ┌▼──────────┐ ┌───▼─────────┐
│                    │HotkeyManager│ │Audio   │ │Transcript.│ │TextInjector │
│                    │(Carbon      │ │Recorder│ │Client     │ │(NSPasteboard│
│                    │ RegisterEve-│ │(AVFound│ │(URLSession│ │ + CGEvent + │
│                    │ ntHotKey)   │ │ ation) │ │ multipart)│ │ AX API)     │
│                    └─────────────┘ └────────┘ └─────┬─────┘ └─────────────┘
│                              ┌──────────────┐       │
│                              │SettingsStore │◀──────┘ (读 API Key)
│                              │(UserDefaults │
│                              │ + Keychain)  │
│                              └──────────────┘
│                              ┌──────────────┐
│                              │PermissionMgr │ (麦克风 + 辅助功能授权引导)
│                              └──────────────┘
└─────────────────────────────────────────────────────────────────┘
```

数据流:热键按下 → Coordinator.startRecording() → 再按 → stopRecording() 得到 `.m4a` 文件 URL → TranscriptionClient.transcribe(url) → 文本 →(可选后处理)→ TextInjector.inject(text) → 状态回 idle,菜单栏图标全程反映状态。

### 1.2 模块职责与接口(Swift 草签)

| 模块 | 职责 | 关键接口 |
|---|---|---|
| **AppCoordinator** | 唯一状态机与编排;所有模块只被它调用,互相不引用 | `func toggleRecording() async`;`var state: AppState`(`idle/recording/transcribing/error(String)`) |
| **HotkeyManager** | 注册/注销全局快捷键;把 Carbon 事件转成回调;快捷键录制(捕获用户按键组合) | `func register(_ hotkey: Hotkey, handler: @escaping () -> Void) throws`;`func unregisterAll()`;`struct Hotkey: Codable { keyCode: UInt32; carbonModifiers: UInt32 }` |
| **AudioRecorder** | AVAudioRecorder 封装;16kHz 单声道 AAC 到临时文件;电平值供 UI 波形/呼吸灯 | `func start() throws`;`func stop() -> URL`;`var averagePower: Float { get }`;`func requestMicPermission() async -> Bool` |
| **TranscriptionClient** | 组 multipart 请求打 `/v1/audio/transcriptions`;错误分类(401/429/网络/超时);注入 prompt 参数 | `func transcribe(fileURL: URL, prompt: String?, language: String?) async throws -> String`;`enum TranscriptionError: LocalizedError` |
| **TextInjector** | 把文本放进前台 App 光标处;粘贴法为主、CGEvent 打字法为备;剪贴板保存/恢复 | `func inject(_ text: String, method: InjectionMethod) async throws`;`enum InjectionMethod { paste, type, auto }` |
| **SettingsStore** | 普通设置进 UserDefaults;API Key 进 Keychain;对外统一 @Observable | `var apiKey: String?`(get/set 走 KeychainHelper);`var hotkey: Hotkey`;`var injectionMethod`;`var autoPunctuation: Bool`;`var removeFillers: Bool` |
| **KeychainHelper** | SecItem 增删改查薄封装 | `static func save(_ value: String, service: String, account: String) throws`;`static func read(...) -> String?`;`static func delete(...)` |
| **PermissionManager** | 麦克风 + 辅助功能权限检测与引导 | `var micAuthorized: Bool`;`var axTrusted: Bool`(`AXIsProcessTrusted()`);`func promptAX()`;`func openSystemSettings(pane:)` |
| **MenuBarUI** | `MenuBarExtra` 图标(状态动画)+ 下拉菜单;Settings 窗口(General / Hotkey / Advanced 三个 tab);首启 onboarding(权限向导) | 纯 SwiftUI,绑定 Coordinator + SettingsStore |

设计规则:模块间零横向依赖,全部经 Coordinator;每个模块可单测(TranscriptionClient 用 URLProtocol mock;TextInjector 用协议抽象 pasteboard/event poster)。

---

## 2. 关键技术决策与坑

### 2.1 全局快捷键:RegisterEventHotKey(推荐)vs NSEvent global monitor

| 方案 | 权限要求 | 能否吞掉按键 | 沙盒 | 坑 |
|---|---|---|---|---|
| **Carbon `RegisterEventHotKey`** ✅ 推荐 | **无需任何权限** | 能(系统级独占) | 沙盒内也可用 | Carbon API 但至今(macOS 15/26)仍受支持;修饰键用 Carbon mask(cmdKey=256, optionKey=2048…)需与 NSEvent.ModifierFlags 互转;不支持"纯修饰键"热键(如双击 Fn) |
| `NSEvent.addGlobalMonitorForEvents(.keyDown)` | **需要辅助功能授权**才能收到 keyDown | **不能**(只旁听,按键仍传给前台 App)→ 会往目标 App 里打进一个多余字符 | 沙盒内基本废 | 观察不消费,做热键体验差,仅适合旁听修饰键 |
| `CGEventTap` | 需要辅助功能/输入监控 | 能 | 不可用(沙盒) | 最强但重;系统在 App 卡顿时会禁用 tap,需监听 `kCGEventTapDisabled*` 重挂 |

**决策**:MVP 用 `RegisterEventHotKey`(默认热键建议 `⌥ + Space` 或 `⌃⌥ + V`,避开 Spotlight 的 `⌘Space`)。toggle 模式:按一下开始、再按结束——比 push-to-talk(按住说话)实现简单且不需要 keyUp 事件。"双击 Fn"这类彩蛋放 backlog(需要 CGEventTap + 输入监控权限,权限链变长)。
坑:热键注册要在主线程;`InstallEventHandler` 的 target 用 `GetEventDispatcherTarget()`;换热键 = 先 `UnregisterEventHotKey` 再注册;与系统/其他 App 冲突时 `RegisterEventHotKey` 返回错误码要提示用户换键。

### 2.2 文字注入:三方案对比(核心难点)

| 方案 | 原理 | 兼容性 | 中文/长文本 | 坑 |
|---|---|---|---|---|
| AX API `kAXSelectedTextAttribute` setValue | 对焦点元素的"选中文本"属性写入 → 等效在光标处插入 | **差**:Electron(VS Code/Slack)、Chromium 网页输入框、Java App、终端大多不支持或 `kAXErrorAttributeUnsupported`;secure field 拒绝 | 支持任意 Unicode | 需辅助功能授权;`AXUIElementCopyAttributeValue(kAXFocusedUIElement)` 拿焦点可能失败;**不要用 `kAXValueAttribute` 整体覆盖**(会清掉用户已有文字) |
| CGEvent 键盘模拟 `CGEventKeyboardSetUnicodeString` | 造一个 keyDown/keyUp 事件对,附带 Unicode 字符串直接 post | 好(绝大多数 App 收 CGEvent) | 中文 OK(绕过输入法直接给字符);**单个事件只可靠携带 ~20 个 UTF-16 code unit**,长文本必须分块 + 每块间 `usleep(~5ms)`,否则丢字/乱序 | 需辅助功能授权;keyCode 填 0 即可;若用户开着中文输入法,个别 App(如某些 IME-aware 编辑器)会出现候选框干扰——实测主流 App 无碍;打字速度感知明显(长段落慢) |
| **剪贴板 + ⌘V** ✅ 推荐主方案 | 文本写 NSPasteboard → CGEvent post ⌘V → 延迟后恢复原剪贴板 | **最好**(凡是支持粘贴的地方都行,含 Electron/网页/终端) | 中文/长文本瞬间完成 | 仍需辅助功能授权(post ⌘V 事件);**必须保存并恢复用户剪贴板**(读出所有 pasteboardItems 快照,200–500ms 后恢复);写入时附加 `org.nspasteboard.ConcealedType` 让剪贴板管理器(Paste/Maccy)忽略;恢复太快会在目标 App 读剪贴板前把内容换掉 → 用 changeCount 轮询或固定 300ms;个别 App 重映射了 ⌘V(少数终端用户自定义)会失效 |

**决策**:`InjectionMethod.auto` = **剪贴板+⌘V 为主**;失败或用户在设置中选择时降级 **CGEvent Unicode 打字法**;AX setValue 不做注入主力,只用 AX 读取焦点元素信息(判断是否 secure field → secure field 时拒绝注入并提示)。三种全部要求辅助功能授权,所以权限引导只需要一次。
坑补充:注入前要确认目标 App 仍是热键按下时的前台 App(用 `NSWorkspace.frontmostApplication` 前后比对,转写期间用户切了窗口就改为"复制到剪贴板+通知"而不是打进错窗口)。

### 2.3 录音格式与上传

- **录音**:`AVAudioRecorder` 写临时文件,settings = `kAudioFormatMPEG4AAC`, 16 kHz, mono, 32 kbps(`AVEncoderBitRateKey: 32000`)。语音转写 16k 单声道足够,AAC 32kbps ≈ **0.24 MB/分钟** → 25 MB 上限可容纳 ~100 分钟,远超单次口述场景(设 App 内硬上限 5 分钟自动停止,防口袋误触烧钱)。
- 为什么不用 WAV:16k/16bit mono WAV ≈ 1.9 MB/分钟,上传慢 8 倍,无精度收益。为什么不用 AVAudioEngine:MVP 不需要实时 buffer;仅为菜单栏电平动画用 `recorder.updateMeters()` 即可。
- **上传**:一次性 multipart/form-data POST(`URLSession.upload`),字段 `file`(audio.m4a)、`model`、`prompt`、`language`、`response_format=json`。**不做流式**:`stream=true` 只是转写结果 SSE 增量返回(音频仍要传完),对"注入一整段文字"的产品形态无收益;真·边说边转要用 Realtime API(websocket),复杂度×3,放 post-MVP。
- 坑:临时文件放 `FileManager.temporaryDirectory`,转写成功后删除(隐私);录音前必须检查输入设备存在(AirPods 切换瞬间可能无输入);`AVAudioApplication.requestRecordPermission`(macOS 14+)拿麦克风授权。

### 2.4 权限链(首启 Onboarding 关键 UX)

1. **麦克风**:Info.plist 必须有 `NSMicrophoneUsageDescription`(缺了直接 crash);Hardened Runtime 下还需 entitlement `com.apple.security.device.audio-input = true`。调用 `AVCaptureDevice.requestAccess(for: .audio)` 触发系统弹窗,一次性。
2. **辅助功能(Accessibility)**:注入必需(post CGEvent / AX 都要)。没有系统弹窗式"授权",只能 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` 触发提示,然后引导用户去 系统设置 → 隐私与安全性 → 辅助功能 手动打开(可用 `NSWorkspace.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)` 直达)。授权状态没有回调 → 用 1s Timer 轮询 `AXIsProcessTrusted()`,变绿后自动进入下一步。**坑**:开发期间每次重新编译签名变化,授权可能失效,需在辅助功能列表里删掉重加;正式版用稳定的 Developer ID 签名就不会。
3. **App Sandbox 必须关闭,原因**:沙盒禁止 (a) 向其他进程 post CGEvent、(b) 通过 AX API 控制其他 App、(c) `AXIsProcessTrusted` 在沙盒内永远拿不到信任。文字注入是产品核心 → 沙盒不可行 → **因此不能上 Mac App Store**(MAS 强制沙盒),走 Developer ID 公证分发(见 §6)。Hardened Runtime 保持开启(公证要求),它与沙盒是两回事,不影响 AX/CGEvent。
4. Onboarding 顺序:欢迎页 → 麦克风(弹窗)→ 辅助功能(引导+轮询)→ 填 API Key(带"测试连接"按钮)→ 展示热键、试一次 → 完成。任一权限缺失时菜单栏图标显示警告角标。

### 2.5 Keychain 存取要点

```swift
// 存(存在则先 SecItemUpdate,失败再 SecItemAdd)
var query: [String: Any] = [
    kSecClass as String:            kSecClassGenericPassword,
    kSecAttrService as String:      "com.yujunzou.ai-voice-input",
    kSecAttrAccount as String:      "openai_api_key",
    kSecUseDataProtectionKeychain as String: true,   // macOS 上强烈建议,走 iOS 式数据保护钥匙串
]
let attrs: [String: Any] = [
    kSecValueData as String:        key.data(using: .utf8)!,
    kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
]
let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
if status == errSecItemNotFound {
    SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
}
// 读: kSecReturnData=true + kSecMatchLimitOne → SecItemCopyMatching
```

要点:绝不进 UserDefaults/plist;`kSecUseDataProtectionKeychain=true` 避免落入旧式 login keychain 弹"允许访问"对话框;错误码要落日志(`errSecMissingEntitlement` 常见于签名/entitlement 配错);UI 里 API Key 用 `SecureField`,只显示尾 4 位;删除 Key 走 `SecItemDelete`。注意:非沙盒 App 用 data-protection keychain 需要 App 有稳定签名(adhoc 重签会读不到旧值,开发期属正常现象)。

---

## 3. OpenAI gpt-4o-transcribe API(WebSearch 核实于 **2026-07-18**)

| 项 | 核实结果 |
|---|---|
| Endpoint | `POST https://api.openai.com/v1/audio/transcriptions`(multipart/form-data) |
| 模型 | `gpt-4o-transcribe`;省钱备选 `gpt-4o-mini-transcribe`;另有 `gpt-4o-transcribe-diarize`(说话人分离,**不支持 prompt**,本产品不用) |
| 必填参数 | `file`(音频文件)、`model` |
| 可选参数 | `prompt`(引导风格/术语,**语言需与音频一致**;中英混输场景给中英混合 prompt)、`language`(ISO-639-1,如 `zh`/`en`;混输时**留空**让模型自动检测更稳)、`temperature`(0–1,转写用 0)、`stream`(SSE 增量返回转写结果)、`include[]=logprobs`(置信度) |
| response_format | `gpt-4o-transcribe` 仅支持 `json` / `text`;**不支持** `verbose_json`/`srt`/`vtt`(那些是 whisper-1 的),因此**没有词级时间戳**——本产品不需要 |
| 文件限制 | ≤ 25 MB;支持 mp3/mp4/m4a/wav/webm/mpeg/mpga |
| 中英混输 | 模型多语言,混合语音可直接转写;prompt 可给出领域词表(如 "QuantConnect, Sharpe, 回测")提升专有名词准确率 |
| 价格 | **$0.006/分钟**(≈ 每天口述 30 分钟 → $5.4/月);`gpt-4o-mini-transcribe` $0.003/分钟。按 token 计价口径:audio input $6/1M tokens、text output $10/1M tokens,折算约等于上述每分钟价 |

来源(2026-07-18 检索):[OpenAI Create transcription API Reference](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create)、[OpenAI Speech-to-text guide](https://developers.openai.com/api/docs/guides/speech-to-text)、[gpt-4o-transcribe model page](https://developers.openai.com/api/docs/models/gpt-4o-transcribe)、[costgoat OpenAI transcription pricing (Jul 2026)](https://costgoat.com/pricing/openai-transcription)。
**计划影响**:response_format 用 `json`;标点/去口头禅优先走 `prompt`(零额外成本);价格低到不需要本地降级方案。

---

## 4. 里程碑分解

| 里程碑 | 内容 | 验收标准 | 预估 |
|---|---|---|---|
| **M0 骨架** | Xcode 工程(§5)、MenuBarExtra 图标+菜单(开始/停止占位、设置、退出)、LSUIElement、AppCoordinator 状态机空转、HotkeyManager 注册默认热键打日志 | App 启动只出现在菜单栏;热键按下控制台打点;⌘Q 干净退出 | 1 天 |
| **M1 录音** | PermissionManager 麦克风授权流;AudioRecorder 完整实现(m4a/16k/mono);热键 toggle 真录音;菜单栏图标 idle→recording 红点+电平动画;5 分钟硬上限 | 热键说 10 秒中文得到可回放的 .m4a(QuickTime 验证);二次授权拒绝时给出引导;无输入设备不 crash | 1.5 天 |
| **M2 转写** | TranscriptionClient(multipart + async/await);错误分类与 UI 提示(401 无效 Key/429 限流/断网/超时 30s);先用临时明文 Key 环境变量 | 对着热键说一句中英混合(“帮我 review 一下这个 PR”)→ 菜单栏通知里出现正确转写文本;拔网线得到人话错误提示 | 1.5 天 |
| **M3 注入** | 辅助功能授权引导+轮询;TextInjector 粘贴法(剪贴板快照/恢复 + ConcealedType)+ CGEvent 打字法 fallback;前台 App 变更保护;secure field 检测拒注 | 在 备忘录 / Safari 输入框 / VS Code / Terminal / 微信 5 个 App 中,热键→说话→文字出现在光标处且原剪贴板内容不丢;密码框场景弹提示不注入 | 2 天 |
| **M4 设置/Keychain** | SettingsStore + KeychainHelper;设置窗口 3 tab(General:API Key+测试连接/注入方式;Hotkey:按键录制控件;Advanced:标点/口头禅/模型选 mini);首启 Onboarding 串起 §2.4 全链 | 全新 macOS 用户账户从 0 走完 onboarding 即可完成一次注入;API Key 重启后仍在(Keychain 验证)且 UserDefaults/plist 里 grep 不到;热键改成 ⌃⌥R 立即生效 | 2 天 |
| **M5 打磨** | 自动标点/去口头禅:第一层用 `prompt`(示例:“请输出带标点的书面文本,去除嗯、呃、like 等口头禅。Punctuate properly; remove filler words.”);A/B 后若不稳定加第二层本地正则后处理(嗯/呃/那个/um/uh 词表);声音反馈(开始/结束提示音 NSSound);错误 toast 统一;图标动效;README+使用说明 | 20 句真实口述样本(10 中 10 混)人工评分:标点正确率 ≥90%,口头禅残留 ≤1 处/句;连续 50 次热键循环无泄漏(Instruments 看内存平稳) | 2 天 |

**合计 ≈ 10 人日**(单人两周)。依赖关系:M1→M2→M3 严格串行;M4 可与 M3 并行一半;M5 收尾。

---

## 5. 项目文件结构 + Xcode 工程创建

### 5.1 目录树

```
ai-voice-input/
├── PLAN.md                          # 本文件
├── README.md                        # M5 补
├── AIVoiceInput.xcodeproj
├── AIVoiceInput/
│   ├── AIVoiceInputApp.swift        # @main, MenuBarExtra + Settings scene
│   ├── AppCoordinator.swift         # 状态机/编排
│   ├── Modules/
│   │   ├── HotkeyManager.swift
│   │   ├── AudioRecorder.swift
│   │   ├── TranscriptionClient.swift
│   │   ├── TextInjector.swift
│   │   ├── SettingsStore.swift
│   │   ├── KeychainHelper.swift
│   │   └── PermissionManager.swift
│   ├── UI/
│   │   ├── MenuBarView.swift        # 下拉菜单内容
│   │   ├── StatusIcon.swift         # 状态图标(SF Symbols: mic / mic.fill / waveform)
│   │   ├── SettingsView.swift       # TabView: General/Hotkey/Advanced
│   │   ├── HotkeyRecorderView.swift # 快捷键录制控件(NSViewRepresentable 捕获 keyDown)
│   │   └── OnboardingView.swift
│   ├── Support/
│   │   ├── TextPostProcessor.swift  # M5: 口头禅正则
│   │   └── Log.swift                # os.Logger 封装
│   ├── Assets.xcassets
│   ├── Info.plist
│   └── AIVoiceInput.entitlements
└── AIVoiceInputTests/
    ├── TranscriptionClientTests.swift   # URLProtocol mock
    ├── KeychainHelperTests.swift
    └── TextPostProcessorTests.swift
```

### 5.2 Xcode 工程创建步骤

1. Xcode → New Project → **macOS App**,Interface: SwiftUI,Language: Swift。Product Name `AIVoiceInput`,**Bundle ID `com.yujunzou.ai-voice-input`**,Team 选个人 Developer ID 账号。Deployment target **macOS 14.0**(要 `@Observable` + `AVAudioApplication`;`MenuBarExtra` 只需 13+)。
2. **Signing & Capabilities**:删除默认的 **App Sandbox capability**(§2.4 原因);保留/开启 **Hardened Runtime**;在 Hardened Runtime 下勾 **Audio Input**(生成 `com.apple.security.device.audio-input`)。
3. **entitlements 最终内容**:仅 `com.apple.security.device.audio-input = true`(注意:文件里**不得出现** `com.apple.security.app-sandbox`)。
4. **Info.plist 键**:
   - `NSMicrophoneUsageDescription` = "需要麦克风录制您的语音以进行转写。"
   - `LSUIElement` (Application is agent) = `YES` → 无 Dock 图标、无主窗口
   - `LSMinimumSystemVersion` = 14.0(模板自带)
5. Build Settings:`SWIFT_STRICT_CONCURRENCY = complete`(新工程默认 Swift 6 即可);链接框架:AVFoundation、Carbon(仅 HotKey 头)、ApplicationServices(AX/CGEvent)、Security——全部系统自带,零第三方依赖。
6. 建 `AIVoiceInputTests` unit test target;Scheme 勾 Test。
7. `git init` + `.gitignore`(xcuserdata/、DerivedData/、*.xcuserstate)。

---

## 6. 分发:Developer ID 签名 + 公证

**为什么不能上 Mac App Store**:MAS 强制 App Sandbox;本产品核心功能(辅助功能注入文字、向其他 App post CGEvent)在沙盒内被系统禁止且 `AXIsProcessTrusted` 永远为 false。市面同类(Raycast、Rectangle、MacWhisper 注入版)同样都是 Developer ID 站外分发。

流程:
1. Apple Developer Program($99/年)→ 生成 **Developer ID Application** 证书装入钥匙串。
2. Xcode Archive → Distribute App → **Direct Distribution(Developer ID)**,自动签名 + Hardened Runtime。
3. 公证(命令行等价流程):
   ```bash
   ditto -c -k --keepParent AIVoiceInput.app AIVoiceInput.zip
   xcrun notarytool submit AIVoiceInput.zip \
     --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
     --password "$APP_SPECIFIC_PW" --wait          # 凭据从环境变量/keychain profile 读,不硬编码
   xcrun stapler staple AIVoiceInput.app            # 钉附票据,离线首启不卡
   spctl -a -vv AIVoiceInput.app                    # 验证: accepted, Notarized Developer ID
   ```
4. 打 DMG(`hdiutil create` 或 create-dmg)→ 同样 notarize+staple DMG → GitHub Releases 发布。
5. 坑:公证要求 Hardened Runtime + 无 `get-task-allow`(Release 配置自动满足);首次分发后**签名要保持稳定**,否则用户的辅助功能授权在升级后失效需重新勾选(TCC 按 code signature 记账)。

---

## 7. 风险表(Top 5)

| # | 风险 | 概率/影响 | 缓解 |
|---|---|---|---|
| 1 | **文字注入在部分 App 失效**(Electron 键位拦截、secure field、远程桌面、个别终端重映射 ⌘V) | 高/高 — 核心功能 | 双通道(粘贴主 + CGEvent 打字备)且用户可切;注入失败自动兜底"文本已复制到剪贴板"+ 通知;M3 验收明确覆盖 5 类代表 App |
| 2 | **辅助功能授权流失败/流失**(用户找不到开关;升级签名变化后 TCC 失效) | 中/高 — 没授权=废 | Onboarding 直达深链 + 轮询自动前进;每次注入前检查 `AXIsProcessTrusted`,失效弹修复引导;发布后固定 Developer ID 签名 |
| 3 | **转写延迟/失败伤体验**(长录音上传慢、429、断网) | 中/中 | 16k/32kbps AAC 压小文件;30s 超时 + 1 次重试;失败保留音频文件并提示可重试;菜单栏状态动画管理预期;录音 5 分钟硬上限 |
| 4 | **中英混输质量不达标**(专有名词、标点风格漂移;prompt 语言不匹配降质) | 中/中 | `language` 留空自动检测;中英混合 prompt + 用户自定义词表(Advanced 设置);M5 20 句样本量化验收;不行再叠本地正则后处理;备选切 `gpt-4o-transcribe` ↔ `mini` A/B |
| 5 | **剪贴板竞态污染用户数据**(恢复过早/过晚;剪贴板管理器抓走转写内容) | 中/中 | 完整 pasteboardItems 快照恢复;`org.nspasteboard.ConcealedType` 标记;300ms 固定延迟 + changeCount 校验;提供"打字法"选项彻底绕开剪贴板 |

次级风险(记录不展开):API Key 泄漏(Keychain+SecureField 已覆盖)、Carbon HotKey API 未来废弃(有 CGEventTap 备选路径)、麦克风被其他 App 独占。

---

## 8. 开工顺序(下一步)

1. 按 §5.2 建工程,提交 M0 骨架
2. M1–M5 每个里程碑一个 feature branch,验收标准过了才合 main
3. M2 起真实调用 OpenAI,`OPENAI_API_KEY` 从环境变量读(开发期),M4 切 Keychain
