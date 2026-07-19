# Owner 亲测清单(agent 在 Background session 无法自测的部分)

> agent 的 shell 在 Background launchd session,**看不到 Aqua 菜单栏、不驱动真实窗口焦点**(FINDINGS §5)。以下几步必须 owner 在**自己的 GUI Terminal.app** 里做一次。全部命令已实测。

```bash
cd /Users/yujunzou/python/python_repo/ai-voice-input
./bundle.sh                        # 出 dist/AIVoiceInput.app
```

## S1 会话 — M0 + M1(录音)

1. `open dist/AIVoiceInput.app`
   - ✅ 菜单栏右侧出现 **mic 图标**;Dock 无图标、⌘Tab 无条目;无权限弹窗
   - 点图标 → 菜单有 状态行 / `开始录音` / `退出`
2. 首次点 `开始录音`(或按 `⌃⌥V`)→ 系统弹 **"AIVoiceInput 想访问麦克风"** → 点 **允许**(one-time,TCC 按 bundle-id 记账)
3. 说 10 秒中文 → 再按 `⌃⌥V` 停 → 菜单出现「转写完成」+「复制上次转写」
   - 说错时按 **Esc** → 「已取消录音」,零 API
   - 全屏 Safari 前台按热键 → 有**开始/结束提示音**(notch/全屏下唯一反馈)

## S2 会话 — M3(注入,**核心**)

**前置授权**:系统设置 → 隐私与安全性 → **辅助功能** → `+` 加你运行用的 **Terminal.app** → 打开开关 → 重启 Terminal。
验证:`./.build/release/aivi-cli probe` 打印 `axTrusted=true`。

1. 自动化 5 用例:
   ```bash
   ./bin/m3_harness.sh
   ```
   期望全 ✅:粘贴法 exact 落字 + 原剪贴板恢复 / 打字法 exact / 密码框拒注不落剪贴板(P0#2)/ Secure Keyboard Entry 拒注 / ⌘V 被吞时不误落。
2. 真实 App 手测(harness 覆盖不到的):`open dist/AIVoiceInput.app`,在 **备忘录 / Safari 地址栏 / Terminal / Discord(或 Claude,Electron 代表)** 里分别:点进输入框 → `⌃⌥V` → 说一句中英混合 → 停 → **文字出现在光标处**,原剪贴板不丢。
   - 微信 4.x = best-effort(自绘渲染 AX 不可靠),落不进就看菜单「复制上次转写」兜底。

## 需要 owner 决策的钱事项(非阻塞,M0–M5 全程免费)

- **Apple Developer Program $99/年**:仅当要①装到第二台 Mac / 给别人用,或②受不了每次重建 .app 重授权辅助功能时才买。三个 blocker(data-protection keychain / 稳定 TCC 授权 / 公证分发)一次购买全解。本机 ad-hoc 开发零阻塞。
