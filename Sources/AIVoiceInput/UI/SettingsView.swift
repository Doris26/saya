import AIVoiceInputCore
import SwiftUI

/// 设置窗:General / Hotkey / Advanced 三 tab(PLAN §4 M4)。
struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsTab(coordinator: coordinator)
                .tabItem { Label("通用", systemImage: "gearshape") }
            HotkeySettingsTab(coordinator: coordinator)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            AdvancedSettingsTab(settings: coordinator.settings)
                .tabItem { Label("高级", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 460, height: 340)
    }
}

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    @State private var apiKeyField = ""
    @State private var testResult = ""
    @State private var testing = false

    private var settings: SettingsStore { coordinator.settings }

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                HStack {
                    SecureField("sk-…", text: $apiKeyField)
                    Button("保存") {
                        settings.apiKey = apiKeyField
                        apiKeyField = ""
                        testResult = "已保存(\(settings.apiKeyMasked))"
                    }
                    .disabled(apiKeyField.isEmpty)
                }
                HStack {
                    Text("当前:\(settings.apiKeyMasked)").foregroundStyle(.secondary)
                    Spacer()
                    Button(testing ? "测试中…" : "测试连接") {
                        testing = true
                        Task {
                            testResult = await coordinator.testAPIKey()
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("注入方式") {
                Picker("注入方式", selection: Binding(
                    get: { settings.injectionMethod },
                    set: { settings.injectionMethod = $0 }
                )) {
                    Text("自动(粘贴优先)").tag("auto")
                    Text("剪贴板 + ⌘V").tag("paste")
                    Text("模拟打字").tag("type")
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Toggle("开机自动启动", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Toggle("显示录音浮层(屏幕底部)", isOn: Binding(
                    get: { settings.showHUD },
                    set: { settings.showHUD = $0; coordinator.applyHUDSetting() }
                ))
            }
            Section("用量 / 花费") {
                let usage = coordinator.usageSummary
                LabeledContent("本月", value: String(
                    format: "%.0f 分钟 · ¥%.2f($%.3f)",
                    usage.monthMinutes, usage.monthCostCNY, usage.monthCostUSD))
                LabeledContent("今日", value: String(
                    format: "%.0f 分钟 · ¥%.2f", usage.todayMinutes, usage.todayCostCNY))
                Text("按音频时长 × 分钟价记账(gpt-4o-transcribe $0.006/min、mini $0.003/min);¥ 按约 7.2 汇率展示。记录存 ~/Library/Application Support/Saya/usage.jsonl。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct HotkeySettingsTab: View {
    let coordinator: AppCoordinator
    @State private var recordError = ""
    @State private var mode: SettingsStore.TriggerMode

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _mode = State(initialValue: coordinator.settings.triggerMode)
    }

    var body: some View {
        Form {
            Section("触发方式") {
                Picker("触发方式", selection: $mode) {
                    Text("🌐 fn 单键 toggle").tag(SettingsStore.TriggerMode.fnKey)
                    Text("自定义组合键").tag(SettingsStore.TriggerMode.combo)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: mode) { _, newMode in
                    coordinator.settings.triggerMode = newMode
                    coordinator.applyHotkeyChange()
                }
            }

            if mode == .fnKey {
                Section {
                    Text("按一下 🌐 fn(地球键)开始录音,再按一下停止。")
                        .font(.caption)
                    Text("⚠️ macOS 默认单按 fn 会触发听写/emoji。请到 系统设置 → 键盘 → 「按下 🌐 键用于」改为「无操作」,fn 单键 toggle 才不会和系统冲突。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("组合键") {
                    HotkeyRecorderView(
                        hotkey: coordinator.settings.hotkey,
                        onRecorded: { newHotkey in
                            do {
                                try Hotkey.validate(keyCode: newHotkey.keyCode,
                                                    carbonModifiers: newHotkey.carbonModifiers)
                                coordinator.settings.hotkey = newHotkey
                                coordinator.applyHotkeyChange()
                                recordError = ""
                            } catch {
                                recordError = error.localizedDescription
                            }
                        }
                    )
                    if !recordError.isEmpty {
                        Text(recordError).font(.caption).foregroundStyle(.red)
                    }
                    Text("按下想用的组合;须含 ⌃ 或 ⌘(系统不允许仅 ⌥/⇧ 的组合)。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("录音时按 Esc 可取消(两种模式通用)。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AdvancedSettingsTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section("转写") {
                Picker("模型", selection: Binding(
                    get: { settings.model },
                    set: { settings.model = $0 }
                )) {
                    Text("gpt-4o-transcribe(质量)").tag("gpt-4o-transcribe")
                    Text("gpt-4o-mini-transcribe(省钱)").tag("gpt-4o-mini-transcribe")
                }
            }
            Section("后处理") {
                Toggle("自动补标点", isOn: Binding(
                    get: { settings.autoPunctuation },
                    set: { settings.autoPunctuation = $0 }
                ))
                Toggle("去除口头禅(嗯/呃/like…)", isOn: Binding(
                    get: { settings.removeFillers },
                    set: { settings.removeFillers = $0 }
                ))
                Text("去口头禅较激进,可能误删内容;逐字场景建议关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
