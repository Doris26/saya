# AI Voice Input

macOS 菜单栏语音输入 App:按全局热键说话 → OpenAI `gpt-4o-transcribe` 转写 → 文字自动输入到当前光标处。中英文混输,无 server,纯本地,只用苹果原生框架 + OpenAI API。

> 本机**无 Xcode**(仅 Command Line Tools),整条构建链走 SwiftPM + 手工 `.app` bundle。所有关键技术点已在本机实测,证据见 `docs/FINDINGS-2026-07-18.md`,对抗性评审见 `docs/GRILL-2026-07-18.md`。

## 快速开始

```bash
# 构建 + 打包
./bundle.sh                          # → dist/AIVoiceInput.app

# 运行
open dist/AIVoiceInput.app           # 菜单栏出现 mic 图标(无 Dock 图标)

# 测试
swift test                           # 29 单测(swift-testing)
```

首次运行走 onboarding:麦克风 → 辅助功能 → 通知 → 触发方式 → 填 OpenAI API Key。

**触发方式**(设置→快捷键 里可切):
- **🌐 fn 单键 toggle(默认)**:按一下 fn 开始录音,再按一下停止 → 转写 → 注入。
  > ⚠️ macOS 默认单按 fn 是听写/emoji。请到 **系统设置 → 键盘 → 「按下 🌐 键用于」→ 无操作**,否则会和系统冲突(onboarding 会引导)。
- **自定义组合键**:如 **⌃⌥V**(录制控件可录任意组合;须含 ⌃ 或 ⌘)。

录音时按 **Esc** 取消(两种模式通用)。

## 权限

| 权限 | 用途 | 怎么给 |
|---|---|---|
| 麦克风 | 录音 | 首次录音弹窗点「允许」 |
| 辅助功能 | 把文字注入到其他 App | 系统设置→隐私与安全性→辅助功能→打开本 App(注入必需) |
| 通知 | 注入结果/错误提示 | onboarding 里允许 |

> **App Sandbox 必须关闭**(注入文字、post CGEvent 在沙盒内被禁),故**不能上 Mac App Store**,走 Developer ID 站外分发(同 Raycast/MacWhisper)。

## 架构

```
触发(fn 单键:CGEventTap listen-only 边沿检测 / 组合键:Carbon RegisterEventHotKey)
  → AudioRecorder(AVAudioRecorder m4a 16k/mono/32kbps)
  → 静音三层 gate(<0.7s 丢弃 / 电平未过底跳过 API / 5min-cap 只通知不注入)
  → TranscriptionClient(multipart → gpt-4o-transcribe,强制简体 prompt)
  → TextInjector(SecureInput gate → secure-field 拒注 → 焦点 recheck → IME gate
                 → 剪贴板+⌘V 主 / CGEvent 打字备)
所有模块经 AppCoordinator(@MainActor @Observable 状态机)编排,互相不引用。
API Key 进 Keychain(legacy 文件钥匙串);设置进 UserDefaults。
```

- `Sources/AIVoiceInputCore/` — 可测 library(热键/录音/转写/注入/设置/Keychain/后处理)
- `Sources/AIVoiceInput/` — thin executable(App/Coordinator/UI)
- `Tools/` — M3 两进程注入验收 harness(`InjectReceiver` + `aivi-cli`)
- `bin/` — 验收脚本(`m3_harness.sh` 注入、`leak_harness.sh` 内存)

## 关键设计决策(实测支撑)

- **注入成功不可探测**(CGEventPost fire-and-forget)→ 兜底 = 转写始终可从菜单「复制上次转写」找回,音频延迟到下次录音才删。
- **密码/Secure 输入拒注绝不落剪贴板**(防口述密码广播)。
- **转写随机吐繁体**(实测同参 5 次 2 次繁体)→ 默认 prompt 强制简体。
- **静音会幻觉**(实测 30s 纯静音 5/5 返回幻觉中文)→ 电平 gate 是 load-bearing 防线。
- **中英混输**:`language` 留空最稳;CJK IME 激活时强制粘贴法(打字法会进拼音缓冲)。

## 分发(需 owner 决策)

M0–M5 全程 ad-hoc 本机开发**零阻塞、免费**。要装到第二台 Mac / 给别人 / 免去每次重建重授权时,买 **Apple Developer Program($99/年)**——一次购买解三锁(data-protection keychain、稳定 TCC 授权、公证分发)。流程见 `PLAN.md §6`。

## 成本

`gpt-4o-transcribe` ≈ $0.006/分钟(每天口述 30 分钟 ≈ $5.4/月);省钱可在高级设置切 `gpt-4o-mini-transcribe`(半价)。
