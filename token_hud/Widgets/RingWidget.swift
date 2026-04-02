// token_hud/Widgets/RingWidget.swift
import SwiftUI

struct RingWidget: View {
    let fraction: Double  // 0.0 – 1.0 (used / total, so remaining = 1 - fraction)
    let label: String
    let size: CGFloat

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)

            // Progress arc (shows remaining, so 1 - fraction)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(1.0 - fraction, 0), 1.0)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)

            // Center label
            Text(label)
                .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }

    private var lineWidth: CGFloat { size * 0.12 }

    private var ringColor: Color {
        // fraction = used/total; low fraction = lots remaining = green
        switch fraction {
        case 0..<0.5:   return .green
        case 0.5..<0.8: return .yellow
        default:         return .red
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        RingWidget(fraction: 0.2, label: "4h", size: 30)
        RingWidget(fraction: 0.6, label: "1h", size: 30)
        RingWidget(fraction: 0.9, label: "5m", size: 30)
    }
    .padding()
    .background(Color.black)
}
