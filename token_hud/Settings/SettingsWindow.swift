// token_hud/Settings/SettingsWindow.swift
import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @Environment(WidgetStore.self) private var widgetStore
    @Environment(AppFilterStore.self) private var appFilterStore

    var body: some View {
        TabView {
            WidgetListEditor()
                .tabItem { Label("小组件", systemImage: "rectangle.3.group") }
            PlatformListView()
                .tabItem { Label("平台", systemImage: "cpu") }
            GeneralSettingsView()
                .environment(appFilterStore)
                .tabItem { Label("通用", systemImage: "gear") }
        }
        .frame(width: 560, height: 520)
        .padding()
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("stateFilePath")   private var stateFilePath   = "~/.token-hud/state.json"
    @AppStorage("refreshInterval") private var refreshInterval = 300
    @Environment(AppFilterStore.self) private var appFilterStore

    var body: some View {
        Form {
            FloatingPanelSection()
            DataSourceSection(stateFilePath: $stateFilePath,
                              refreshInterval: $refreshInterval,
                              browseFile: browseFile)
            AppearanceSection()
            AppFilterSettingsView()
                .environment(appFilterStore)
            SystemSection()
        }
        .formStyle(.grouped)
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            stateFilePath = url.path
        }
    }
}

// MARK: - Floating Panel Section

private struct FloatingPanelSection: View {
    @AppStorage("floatingPanelEnabled") private var enabled = true
    @AppStorage("floatingHotkeyKeyCode") private var keyCode = -1
    @AppStorage("floatingHotkeyModifiers") private var modifiers = 0
    @AppStorage("floatingPanelScale") private var scale = 1.0
    @AppStorage("overlayMode") private var overlayMode = "compact"

    var body: some View {
        Section("浮动面板") {
            Toggle("启用浮动面板", isOn: $enabled)
            if enabled {
                Picker("显示模式", selection: $overlayMode) {
                    Text("紧凑").tag("compact")
                    Text("分组").tag("grouped")
                }
                .pickerStyle(.segmented)
                KeyRecorder(label: "快捷键", keyCode: $keyCode, modifiers: $modifiers)
                Picker("缩放", selection: $scale) {
                    Text("0.5x").tag(0.5)
                    Text("0.75x").tag(0.75)
                    Text("1x").tag(1.0)
                    Text("1.5x").tag(1.5)
                    Text("2x").tag(2.0)
                }
                .pickerStyle(.menu)
            }
        }
    }
}

// MARK: - Data Source Section

private struct DataSourceSection: View {
    @Binding var stateFilePath: String
    @Binding var refreshInterval: Int
    var browseFile: () -> Void

    var body: some View {
        Section("数据源") {
            HStack {
                TextField("state.json 路径", text: $stateFilePath)
                Button("浏览…") { browseFile() }
            }
            Text("token-hud 守护进程写入的 state.json 文件路径。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("刷新间隔", selection: $refreshInterval) {
                Text("10 秒").tag(10)
                Text("30 秒").tag(30)
                Text("1 分钟").tag(60)
                Text("2 分钟").tag(120)
                Text("5 分钟").tag(300)
            }
            .pickerStyle(.menu)
            Text("同时控制界面更新和 Codex 数据拉取的频率。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Appearance Section

private struct AppearanceSection: View {
    @AppStorage("hudOpacity")      private var hudOpacity      = 1.0
    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0

    var body: some View {
        Section("外观") {
            HStack {
                Text("透明度")
                Slider(value: $hudOpacity, in: 0.2...1.0, step: 0.05)
                Text("\(Int(hudOpacity * 100))%")
                    .frame(width: 36, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            Picker("小组件大小", selection: $widgetSizeScale) {
                Text("小").tag(0.75)
                Text("中").tag(1.0)
                Text("大").tag(1.25)
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - System Section

private struct SystemSection: View {
    var body: some View {
        Section("系统") {
            if #available(macOS 13, *) {
                LaunchAtLoginToggle()
            }
        }
    }
}

// MARK: - Key Recorder

private struct KeyRecorder: View {
    let label: String
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                isRecording.toggle()
                if isRecording { startRecording() }
                else           { stopRecording() }
            } label: {
                Text(displayString)
                    .foregroundStyle(isRecording ? .white : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.accentColor : Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if keyCode >= 0 {
                Button(role: .destructive) {
                    keyCode = -1
                    modifiers = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayString: String {
        guard keyCode >= 0 else { return "点击录制…" }
        return KeyRecorder.format(keyCode: keyCode, modifiers: modifiers)
    }

    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                let cleanMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if !cleanMods.isEmpty {
                    keyCode = Int(event.keyCode)
                    modifiers = Int(cleanMods.rawValue)
                    stopRecording()
                    return nil
                }
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    static func format(keyCode: Int, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var parts: [String] = []
        if flags.contains(.control)   { parts.append("⌃") }
        if flags.contains(.option)    { parts.append("⌥") }
        if flags.contains(.shift)     { parts.append("⇧") }
        if flags.contains(.command)   { parts.append("⌘") }
        parts.append(displayKeyName(UInt16(keyCode)))
        return parts.joined()
    }

    private static func displayKeyName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Escape", 54: "⌘", 55: "⌘",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 115: "Home", 116: "PageUp",
            117: "ForwardDelete", 119: "End", 120: "F2", 121: "PageDown",
            122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }
}

// MARK: - Launch at Login

@available(macOS 13, *)
private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("登录时启动", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else        { try SMAppService.mainApp.unregister() }
                } catch {
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
