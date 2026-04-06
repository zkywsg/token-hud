// token_hud/Settings/PlatformListView.swift
import SwiftUI

struct PlatformListView: View {
    // "claude" starts expanded by default
    @State private var expandedIDs: Set<String> = ["claude"]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(PlatformConfig.all) { platform in
                    PlatformRowView(
                        platform: platform,
                        isExpanded: Binding(
                            get: { expandedIDs.contains(platform.id) },
                            set: { expanded in
                                if expanded { expandedIDs.insert(platform.id) }
                                else { expandedIDs.remove(platform.id) }
                            }
                        )
                    )
                }

                // Placeholder for future platforms
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.secondary)
                    Text("More platforms coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
    }
}
