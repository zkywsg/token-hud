// token_hud/Settings/SettingsWindow.swift
import SwiftUI

struct SettingsWindow: View {
    @Environment(WidgetStore.self) private var widgetStore
    @Environment(AppFilterStore.self) private var appFilterStore

    var body: some View {
        TabView {
            WidgetListEditor()
                .tabItem { Label("Widgets", systemImage: "rectangle.3.group") }
            PlatformListView()
                .tabItem { Label("Platforms", systemImage: "cpu") }
            AppFilterSettingsView()
                .environment(appFilterStore)
                .tabItem { Label("App Filter", systemImage: "app.badge") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 520, height: 480)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("stateFilePath")   private var stateFilePath   = "~/.token-hud/state.json"
    @AppStorage("refreshInterval") private var refreshInterval = 300

    var body: some View {
        Form {
            Section("Data Source") {
                HStack {
                    TextField("state.json path", text: $stateFilePath)
                    Button("Browse…") { browseFile() }
                }
            }
            Section("Refresh Interval") {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("5 minutes").tag(300)
                }
                .pickerStyle(.menu)
                Text("Controls both UI updates and Codex data fetch frequency.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
