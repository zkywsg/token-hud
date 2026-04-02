// token_hud/Settings/SettingsWindow.swift
import SwiftUI

struct SettingsWindow: View {
    @Environment(WidgetStore.self) private var widgetStore

    var body: some View {
        TabView {
            WidgetListEditor()
                .tabItem { Label("Widgets", systemImage: "rectangle.3.group") }
            ServiceConfigView()
                .tabItem { Label("Services", systemImage: "key") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 420)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("stateFilePath")   private var stateFilePath   = "~/.token-hud/state.json"
    @AppStorage("refreshInterval") private var refreshInterval = 60

    var body: some View {
        Form {
            Section("Data Source") {
                HStack {
                    TextField("state.json path", text: $stateFilePath)
                    Button("Browse…") { browseFile() }
                }
            }
            Section("Daemon Interval") {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("5 minutes").tag(300)
                }
                .pickerStyle(.menu)
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
