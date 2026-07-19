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
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct HotkeySettingsTab: View {
    let coordinator: AppCoordinator
    @State private var recordError = ""

    var body: some View {
        Form {
            Section("录音开始/停止热键") {
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
                Text("按下想用的组合;须含 ⌃ 或 ⌘(系统不允许仅 ⌥/⇧ 的组合)。录音时按 Esc 可取消。")
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
