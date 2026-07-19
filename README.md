# Saya

*English · [中文](README.zh.md)*

**Bilingual voice-to-text for macOS. Press `fn`, speak, and your words land at the cursor.** A menu-bar app — fully local, no server, built only on Apple-native frameworks + the OpenAI API.

> Built for **mixing English and 中文 in one breath** — a sentence like "帮我 review this PR then merge 到 main" transcribes cleanly. **Pay-as-you-go at ~$0.006/min** — 30 minutes of dictation a day runs about **$5/month**, with no subscription and no monthly fee.

## Why Saya

| | Saya | Subscription dictation apps (e.g. Wispr Flow) |
|---|---|---|
| **Chinese + English mixed** | ✅ Native — mixed-language sentences stay accurate | Usually English-first |
| **Price** | **Pay-as-you-go ≈ $0.006/min**, pay for what you use | Fixed **$12–15/month** subscription |
| **Data** | Local-only; audio is deleted on the next recording, and only that clip is sent to OpenAI to transcribe | Varies by product |
| **Trigger** | `fn` single-key toggle (or a custom shortcut) | Varies |
| **Open source** | ✅ Full source — build and sign it yourself | ❌ |
| **UI** | Bilingual (中/EN), switch instantly in Settings | — |

## Quick start

```bash
git clone https://github.com/Doris26/saya.git
cd saya
./bundle.sh                     # → dist/Saya.app
open dist/Saya.app              # a 🎙️ icon appears in the menu bar (no Dock icon)
```

> Requires macOS 14+ and Swift 6.1+ (Command Line Tools are enough — **no Xcode needed**). If `swift --version` runs, you're set.

First launch walks you through: Microphone → Accessibility → Notifications → Trigger → OpenAI API key.

**Trigger** (switchable in Settings → Shortcut):
- **🌐 `fn` single-key toggle (default)**: press `fn` once to start recording, again to stop → transcribe → insert at the cursor.
  > ⚠️ macOS uses a single `fn` press for dictation/emoji by default. Go to **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing** (onboarding reminds you).
- **Custom shortcut**: e.g. **⌃⌥V** (record any combo; must include ⌃ or ⌘).

Press **Esc** while recording to cancel. The menu-bar icon reflects state: 🎙️ idle / 🔴 recording / ⏳ transcribing / ⚠️ error.

**Recording overlay**: a small pill appears at the bottom of the screen the instant you press the trigger (an instant receipt for the "invisible" `fn` key), showing 🔴 Listening + a live audio waveform + a timer, then flashing "✓ Inserted" before fading out. It **never steals focus and is click-through**, so it can't disturb the window you're typing into. Toggle it off in Settings.

**Cost tracking**: the menu and Settings show cumulative minutes and spend for this month and today (in $ and ¥). You use your own API key and pay per use — fully transparent. Records are stored locally at `~/Library/Application Support/Saya/usage.jsonl`.

**Interface language**: 中文 / English / follow system — switch in Settings → General, applied instantly.

## Pricing / cost

- **`gpt-4o-transcribe` ≈ $0.006/min**.
- ~30 min of dictation a day ≈ **$5.4/month**; occasional use is barely noticeable.
- To save more, switch to **`gpt-4o-mini-transcribe` (half price)** in Advanced settings.
- You only pay OpenAI's transcription fee — **the app itself is free, no subscription, no markup.** Bring your own API key; costs are fully visible.

## Chinese + English support

- **Mixing Chinese and English in one sentence** is the core design case (common in tech dictation: "把这个 function 重构一下, then merge 到 main").
- The default prompt enforces **Simplified Chinese + automatic punctuation** (OpenAI occasionally returns Traditional Chinese; the prompt locks it to Simplified).
- When a CJK input method is active, Saya inserts via paste (so text doesn't fall into the pinyin buffer).
- Leaving `language` unset is the most robust — the model decides the Chinese/English boundary itself.

## Permissions

| Permission | Purpose | How to grant |
|---|---|---|
| Microphone | Recording | Click "Allow" on the first-recording prompt |
| Accessibility | Insert text into other apps | System Settings → Privacy & Security → Accessibility → enable Saya (required for insertion) |
| Notifications | Insertion result / error alerts | Allow during onboarding |

> App Sandbox must be off (inserting text and posting CGEvents is forbidden inside the sandbox), so Saya ships outside the Mac App Store (like Raycast / MacWhisper).

## Architecture

```
Trigger (fn: CGEventTap edge detection / combo: Carbon RegisterEventHotKey)
  → AudioRecorder (AVAudioRecorder m4a 16k/mono/32kbps)
  → 3-layer silence gate (<0.7s discard / below noise floor skip API / 5-min cap notify-only)
  → TranscriptionClient (multipart → gpt-4o-transcribe, Simplified-Chinese prompt)
  → TextInjector (SecureInput gate → secure-field refusal → focus recheck → IME gate
                  → clipboard+⌘V primary / CGEvent typing fallback)
All modules are orchestrated by AppCoordinator (a @MainActor @Observable state machine); they never reference each other.
API key lives in the Keychain; settings in UserDefaults; all user-facing strings go through L10n (zh/en).
```

- `Sources/AIVoiceInputCore/` — testable library (hotkey / recording / transcription / injection / settings / Keychain / post-processing / L10n)
- `Sources/AIVoiceInput/` — thin executable (App / Coordinator / UI)
- `Tools/` — injection acceptance harness (`InjectReceiver` + `aivi-cli`)
- `bin/` — acceptance scripts (`m3_harness.sh` injection, `leak_harness.sh` memory)

```bash
swift test                      # unit tests
```

## Key design decisions (empirically backed)

- **Insertion success is undetectable** (CGEventPost is fire-and-forget) → fallback = the transcript is always recoverable from the menu's "Copy last transcript".
- **Secure/password fields are refused and never touch the clipboard** (prevents broadcasting a spoken password).
- **Silence hallucinates** (measured: 30s of pure silence returned hallucinated Chinese 5/5 times) → the level gate is a load-bearing defense.
- **Random Traditional Chinese output** → the default prompt forces Simplified.

## Distribution

Local ad-hoc development is **free and unblocked**. To install on a second Mac, share with others, or avoid re-granting permissions on every rebuild, buy the **Apple Developer Program ($99/yr)** — one purchase unlocks all three (Keychain, stable TCC grants, notarized distribution). See `PLAN.md §6`.

---

MIT License · Bring your own OpenAI API key; your data never passes through a third-party server.
