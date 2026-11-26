import SwiftUI

struct BatteryPercentageIcon: View {
    let percentage: UInt8?
    var size: CGFloat = 18
    var color: Color = .secondary

    private var accessibilityText: String {
        guard let percentage, percentage <= 100 else { return "Mac battery unavailable" }
        return "Mac battery, \(percentage) percent"
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.13)
                    .stroke(color, lineWidth: max(1, size * 0.08))
                Text(percentage.map { $0 <= 100 ? "\($0)%" : "—" } ?? "—")
                    .font(.system(size: size * 0.48, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, size * 0.12)
            }
            .frame(width: size * 2, height: size)

            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(color)
                .frame(width: size * 0.12, height: size * 0.34)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
