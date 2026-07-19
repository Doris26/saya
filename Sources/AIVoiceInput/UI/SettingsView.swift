import AIVoiceInputCore
import SwiftUI

/// 设置窗:General / Hotkey / Advanced 三 tab(PLAN §4 M4)。
struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        let l = coordinator.l10n
        TabView {
            GeneralSettingsTab(coordinator: coordinator)
                .tabItem { Label(l.t(.tabGeneral), systemImage: "gearshape") }
            HotkeySettingsTab(coordinator: coordinator)
                .tabItem { Label(l.t(.tabShortcut), systemImage: "keyboard") }
            AdvancedSettingsTab(coordinator: coordinator)
                .tabItem { Label(l.t(.tabAdvanced), systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    @State private var apiKeyField = ""
    @State private var testResult = ""
    @State private var testing = false

    private var settings: SettingsStore { coordinator.settings }

    var body: some View {
        let l = coordinator.l10n
        Form {
            Section(l.t(.secLanguage)) {
                Picker(l.t(.langLabel), selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }   // @Observable → 即时重渲染
                )) {
                    Text(l.t(.langSystem)).tag(AppLanguage.system)
                    Text(l.t(.langZh)).tag(AppLanguage.zh)
                    Text(l.t(.langEn)).tag(AppLanguage.en)
                }
            }
            Section(l.t(.secAPIKey)) {
                let hasKey = !settings.effectiveAPIKey.isEmpty
                HStack {
                    SecureField(hasKey ? l.t(.apiKeyPlaceholderHas) : l.t(.apiKeyPlaceholderEmpty), text: $apiKeyField)
                    Button(l.t(.btnSave)) {
                        settings.apiKey = apiKeyField
                        apiKeyField = ""
                        testResult = l.t(.savedMasked, settings.apiKeyMasked)
                    }
                    .disabled(apiKeyField.isEmpty)
                }
                HStack {
                    if hasKey {
                        Label(l.t(.labelSaved, settings.apiKeyMasked), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text(l.t(.labelNotConfigured)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(testing ? l.t(.btnTesting) : l.t(.btnTest)) {
                        testing = true
                        Task {
                            testResult = await coordinator.testAPIKey()
                            testing = false
                        }
                    }
                    .disabled(testing || !hasKey)
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(l.t(.secInjection)) {
                Picker(l.t(.secInjection), selection: Binding(
                    get: { settings.injectionMethod },
                    set: { settings.injectionMethod = $0 }
                )) {
                    Text(l.t(.injAuto)).tag("auto")
                    Text(l.t(.injPaste)).tag("paste")
                    Text(l.t(.injType)).tag("type")
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Toggle(l.t(.toggleLaunch), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Toggle(l.t(.toggleHUD), isOn: Binding(
                    get: { settings.showHUD },
                    set: { settings.showHUD = $0; coordinator.applyHUDSetting() }
                ))
            }
            Section(l.t(.secUsage)) {
                let usage = coordinator.usageSummary
                LabeledContent(l.t(.usageMonth), value: l.t(.usageMonthValue,
                    usage.monthMinutes, usage.monthCostCNY, usage.monthCostUSD))
                LabeledContent(l.t(.usageToday), value: l.t(.usageTodayValue,
                    usage.todayMinutes, usage.todayCostCNY, usage.todayCostUSD))
                Text(l.t(.usageNote)).font(.caption).foregroundStyle(.secondary)
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
        let l = coordinator.l10n
        Form {
            Section(l.t(.secTrigger)) {
                Picker(l.t(.secTrigger), selection: $mode) {
                    Text(l.t(.trigFn)).tag(SettingsStore.TriggerMode.fnKey)
                    Text(l.t(.trigCombo)).tag(SettingsStore.TriggerMode.combo)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: mode) { _, newMode in
                    coordinator.settings.triggerMode = newMode
                    coordinator.applyHotkeyChange()
                }
            }

            if mode == .fnKey {
                Section {
                    Text(l.t(.fnHint1)).font(.caption)
                    Text(l.t(.fnHint2)).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(l.t(.secCombo)) {
                    HotkeyRecorderView(
                        hotkey: coordinator.settings.hotkey,
                        prompt: l.t(.recorderPrompt),
                        onRecorded: { newHotkey in
                            do {
                                try Hotkey.validate(keyCode: newHotkey.keyCode,
                                                    carbonModifiers: newHotkey.carbonModifiers)
                                coordinator.settings.hotkey = newHotkey
                                coordinator.applyHotkeyChange()
                                recordError = ""
                            } catch let error as Hotkey.ValidationError {
                                recordError = error.localized(l)
                            } catch {
                                recordError = error.localizedDescription
                            }
                        }
                    )
                    if !recordError.isEmpty {
                        Text(recordError).font(.caption).foregroundStyle(.red)
                    }
                    Text(l.t(.comboHint)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Text(l.t(.escHint)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AdvancedSettingsTab: View {
    let coordinator: AppCoordinator
    private var settings: SettingsStore { coordinator.settings }

    var body: some View {
        let l = coordinator.l10n
        Form {
            Section(l.t(.secTranscribe)) {
                Picker(l.t(.modelLabel), selection: Binding(
                    get: { settings.model },
                    set: { settings.model = $0 }
                )) {
                    Text(l.t(.modelQuality)).tag("gpt-4o-transcribe")
                    Text(l.t(.modelCheap)).tag("gpt-4o-mini-transcribe")
                }
            }
            Section(l.t(.secPost)) {
                Toggle(l.t(.togglePunct), isOn: Binding(
                    get: { settings.autoPunctuation },
                    set: { settings.autoPunctuation = $0 }
                ))
                Toggle(l.t(.toggleFillers), isOn: Binding(
                    get: { settings.removeFillers },
                    set: { settings.removeFillers = $0 }
                ))
                Text(l.t(.fillersHint)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
