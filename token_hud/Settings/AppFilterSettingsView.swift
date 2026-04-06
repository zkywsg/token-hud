// token_hud/Settings/AppFilterSettingsView.swift
import SwiftUI
import AppKit

struct AppFilterSettingsView: View {
    @Environment(AppFilterStore.self) private var store
    @State private var showRunningAppsSheet = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("只在特定 App 里显示 HUD", isOn: $store.isFilterEnabled)
            }

            if store.isFilterEnabled {
                Section("允许的 App") {
                    if store.allowedApps.isEmpty {
                        Text("还没有添加任何 App")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.allowedApps) { app in
                            AllowedAppRow(app: app) {
                                store.removeApp(app.bundleIdentifier)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Button("从运行中的 App 选择…") {
                            showRunningAppsSheet = true
                        }
                        Button("从应用程序文件夹选择…") {
                            pickFromApplicationsFolder()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showRunningAppsSheet) {
            RunningAppsPickerSheet { app in
                store.addApp(app)
            }
        }
    }

    private func pickFromApplicationsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let plist = NSDictionary(contentsOf: infoPlistURL),
            let bundleID = plist["CFBundleIdentifier"] as? String
        else { return }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        store.addApp(AllowedApp(bundleIdentifier: bundleID, name: name))
    }
}

// MARK: - Allowed App Row

private struct AllowedAppRow: View {
    let app: AllowedApp
    let onRemove: () -> Void

    var body: some View {
        HStack {
            AppIconView(bundleIdentifier: app.bundleIdentifier)
                .frame(width: 20, height: 20)
            Text(app.name)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - App Icon

private struct AppIconView: View {
    let bundleIdentifier: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var icon: NSImage {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

// MARK: - Running Apps Picker Sheet

private struct RunningAppsPickerSheet: View {
    let onSelect: (AllowedApp) -> Void
    @Environment(\.dismiss) private var dismiss

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择 App")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding()

            Divider()

            List(runningApps, id: \.bundleIdentifier) { app in
                Button {
                    guard let bundleID = app.bundleIdentifier else { return }
                    let name = app.localizedName ?? bundleID
                    onSelect(AllowedApp(bundleIdentifier: bundleID, name: name))
                    dismiss()
                } label: {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 340, height: 400)
    }
}
