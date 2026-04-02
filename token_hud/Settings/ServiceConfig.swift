// token_hud/Settings/ServiceConfig.swift
import SwiftUI

struct ServiceConfigView: View {
    @State private var extractionState: ExtractionState = .idle
    @State private var storedKey: String? = nil
    @State private var selectedBrowser: BrowserType = .safari
    private let extractor = SessionKeyExtractor()

    enum ExtractionState: Equatable {
        case idle, extracting
        case success(BrowserType), failed(String)
    }

    var body: some View {
        Form {
            Section("Claude Pro — Session Key") {
                HStack {
                    Text("Status")
                    Spacer()
                    statusBadge
                }
                Picker("Extract from browser", selection: $selectedBrowser) {
                    ForEach(BrowserType.allCases) { b in Text(b.rawValue).tag(b) }
                }
                Button(extractionState == .extracting ? "Extracting…" : "Extract Session Key") {
                    runExtraction()
                }
                .disabled(extractionState == .extracting)
                if case .failed(let msg) = extractionState {
                    Text(msg).font(.caption).foregroundColor(.red)
                }
            }
            Section("Manual Entry") {
                SecureField("Paste sessionKey value", text: Binding(
                    get: { storedKey ?? "" },
                    set: { v in
                        guard !v.isEmpty else { return }
                        Task {
                            try? await extractor.storeInKeychain(sessionKey: v)
                            try? await extractor.writeConfigFile(sessionKey: v)
                            storedKey = v
                        }
                    }
                ))
                Text("Open claude.ai → DevTools → Application → Cookies → copy `sessionKey`")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { storedKey = await extractor.loadFromKeychain() }
    }

    @ViewBuilder private var statusBadge: some View {
        switch extractionState {
        case .idle:
            Text(storedKey != nil ? "Configured" : "Not configured")
                .foregroundColor(storedKey != nil ? .green : .secondary)
        case .extracting:
            ProgressView().controlSize(.small)
        case .success(let b):
            Text("Found in \(b.rawValue)").foregroundColor(.green)
        case .failed:
            Text("Failed").foregroundColor(.red)
        }
    }

    private func runExtraction() {
        extractionState = .extracting
        Task {
            do {
                if let (browser, key) = try await extractor.extractFromBrowser(selectedBrowser) {
                    try await extractor.storeInKeychain(sessionKey: key)
                    try await extractor.writeConfigFile(sessionKey: key)
                    storedKey = key
                    extractionState = .success(browser)
                } else {
                    extractionState = .failed("Not found in \(selectedBrowser.rawValue). Try another browser or paste manually.")
                }
            } catch {
                extractionState = .failed(error.localizedDescription)
            }
        }
    }
}
