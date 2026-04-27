// token_hud/Settings/PlatformListView.swift
import SwiftUI

struct PlatformListView: View {
    @State private var expandedIDs: Set<String> = ["claude"]
    @State private var selectedAPIPlatform: String = "openai"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Group 1: Claude
                PlatformRowView(
                    platform: PlatformConfig.all.first { $0.id == "claude" }!,
                    isExpanded: Binding(
                        get: { expandedIDs.contains("claude") },
                        set: { expanded in
                            if expanded { expandedIDs.insert("claude") }
                            else { expandedIDs.remove("claude") }
                        }
                    )
                )

                // Group 2: API Key Platforms
                APIKeyGroupView(selectedPlatform: $selectedAPIPlatform)

                // Group 3: Codex
                PlatformRowView(
                    platform: PlatformConfig.all.first { $0.id == "codex" }!,
                    isExpanded: Binding(
                        get: { expandedIDs.contains("codex") },
                        set: { expanded in
                            if expanded { expandedIDs.insert("codex") }
                            else { expandedIDs.remove("codex") }
                        }
                    )
                )
            }
            .padding()
        }
    }
}
