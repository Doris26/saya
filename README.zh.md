# Saya

*[English](README.md) · 中文*

**中英文语音输入,按 `fn` 说话,文字直接落到光标处。** macOS 菜单栏小工具,纯本地、无服务器,只用苹果原生框架 + OpenAI API。

> 为**中英文混说**而生 —— 一句话里中英夹杂("帮我 review 这个 PR")照样准。**按量付费,每分钟约 ¥0.04($0.006)**,重度用一天口述 30 分钟也就几块钱一个月,没有订阅、没有月费。

## 为什么用它

| | Saya | 订阅制听写 App(如 Wispr Flow) |
|---|---|---|
| **中英文混说** | ✅ 原生,一句话里中英夹杂照样准 | 多为英文优先 |
| **价格** | **按量付费 ≈ ¥0.04/分钟**,用多少付多少 | 订阅 $12–15/月固定 |
| **数据** | 纯本地,音频不留存(下次录音即删),只把该段音频发 OpenAI 转写 | 依产品而定 |
| **触发** | `fn` 单键 toggle(或自定义组合键) | 各异 |
| **开源** | ✅ 代码全公开,自己编自己签 | ❌ |

## 快速开始

```bash
git clone https://github.com/Doris26/saya.git
cd saya
./bundle.sh                          # → dist/Saya.app
open dist/Saya.app              # 菜单栏出现 🎙️ 图标(无 Dock 图标)
```

> 需 macOS 14+ 与 Swift 6.1+(命令行工具即可,**不需要 Xcode**)。`swift --version` 能跑就行。

首次运行走引导:麦克风 → 辅助功能 → 通知 → 触发方式 → 填 OpenAI API Key。

**触发方式**(设置 → 快捷键 里可切):
- **🌐 `fn` 单键 toggle(默认)**:按一下 `fn` 开始录音,再按一下停止 → 转写 → 注入到光标处。
  > ⚠️ macOS 默认单按 `fn` 是听写/emoji。请到 **系统设置 → 键盘 →「按下 🌐 键用于」→ 无操作**(引导里会提示)。
- **自定义组合键**:如 **⌃⌥V**(可录任意组合;须含 ⌃ 或 ⌘)。

录音时按 **Esc** 取消。菜单栏图标随状态变:🎙️ 待命 / 🔴 录音 / ⏳ 转写 / ⚠️ 出错。

**界面语言**:中文 / English / 跟随系统,设置 → 通用里切换,即时生效。

**录音浮层**:屏幕底部会弹出一个小浮窗——按下触发键那一刻立即出现(给「看不见的 fn 键」一个即时回执),显示 🔴 正在听 + 实时电平波形 + 计时,转写完成闪现「✓ 已输入」后淡出。**不抢焦点、点击穿透**,不影响你正在打字的窗口。设置里可关。

**花费追踪**:菜单栏下拉和设置里显示本月/今日累计分钟数与花费(¥ 和 $),用自己的 API Key、按量计费,一目了然。记录存本地 `~/Library/Application Support/Saya/usage.jsonl`。

## 价格 / 成本

- **模型 `gpt-4o-transcribe` ≈ $0.006/分钟(约 ¥0.04)**。
- 一天口述 30 分钟 ≈ **$5.4/月**;偶尔用基本感觉不到花钱。
- 省钱可在高级设置切 **`gpt-4o-mini-transcribe`(半价)**。
- 你只出 OpenAI 的转写费,**App 本身免费、无订阅、无抽成**。用自己的 API Key,花费一目了然。

## 中英文支持

- 一句话里**中英夹杂**是设计的核心场景(技术口述常见:"把这个 function 重构一下,然后 merge 到 main")。
- 默认 prompt 强制**简体中文 + 自动标点**(实测 OpenAI 有时随机吐繁体,已在 prompt 层锁死简体)。
- CJK 输入法激活时自动走粘贴注入(避免文字掉进拼音缓冲)。
- `language` 留空最稳,让模型自行判定中/英边界。

## 权限

| 权限 | 用途 | 怎么给 |
|---|---|---|
| 麦克风 | 录音 | 首次录音弹窗点「允许」 |
| 辅助功能 | 把文字注入到其他 App | 系统设置→隐私与安全性→辅助功能→打开 Saya(注入必需) |
| 通知 | 注入结果/错误提示 | 引导里允许 |

> App Sandbox 必须关闭(注入文字、post CGEvent 在沙盒内被禁),故走站外分发,不上 Mac App Store(同 Raycast/MacWhisper)。

## 架构

```
触发(fn 单键:CGEventTap 边沿检测 / 组合键:Carbon RegisterEventHotKey)
  → AudioRecorder(AVAudioRecorder m4a 16k/mono/32kbps)
  → 静音三层 gate(<0.7s 丢弃 / 电平未过底跳过 API / 5min-cap 只通知不注入)
  → TranscriptionClient(multipart → gpt-4o-transcribe,强制简体 prompt)
  → TextInjector(SecureInput gate → secure-field 拒注 → 焦点 recheck → IME gate
                 → 剪贴板+⌘V 主 / CGEvent 打字备)
所有模块经 AppCoordinator(@MainActor @Observable 状态机)编排,互相不引用。
API Key 进 Keychain;设置进 UserDefaults。
```

- `Sources/AIVoiceInputCore/` — 可测 library(热键/录音/转写/注入/设置/Keychain/后处理)
- `Sources/AIVoiceInput/` — thin executable(App/Coordinator/UI)
- `Tools/` — 注入验收 harness(`InjectReceiver` + `aivi-cli`)
- `bin/` — 验收脚本(`m3_harness.sh` 注入、`leak_harness.sh` 内存)

```bash
swift test                           # 单元测试
```

## 关键设计决策(实测支撑)

- **注入成功不可探测**(CGEventPost fire-and-forget)→ 兜底 = 转写始终可从菜单「复制上次转写」找回。
- **密码/Secure 输入拒注绝不落剪贴板**(防口述密码广播)。
- **静音会幻觉**(实测 30s 纯静音 5/5 返回幻觉中文)→ 电平 gate 是 load-bearing 防线。
- **随机吐繁体** → 默认 prompt 强制简体。

## 分发

本机 ad-hoc 开发**零阻塞、免费**。要装到第二台 Mac / 给别人 / 免去每次重建重授权,买 **Apple Developer Program($99/年)** 一次解三锁(keychain、稳定 TCC 授权、公证分发)。见 `PLAN.md §6`。

---

MIT License · 用自己的 OpenAI API Key,数据不经第三方服务器。
