import SwiftUI

struct CountdownWidget: View {
    let fraction: Double
    let label: String

    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0

    private var color: Color {
        if fraction >= 0.8 { return .red }
        if fraction >= 0.5 { return .yellow }
        return .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3 * widgetSizeScale)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 3 * widgetSizeScale, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Text(label)
                .font(.system(size: 9 * widgetSizeScale, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
        .frame(width: 36 * widgetSizeScale, height: 36 * widgetSizeScale)
    }
}
