import SwiftUI

struct AppScreenView: View {
    let onAuthenticate: () -> Void
    @ObservedObject var batteryMonitor: MacBatteryMonitor
    let safeAreaTopInset: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.105, green: 0.112, blue: 0.128), Color(red: 0.035, green: 0.039, blue: 0.047)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                let compact = geometry.size.height < 600 || geometry.size.width < 700
                let scale = min(1, max(0.68, min(geometry.size.width / 1200, geometry.size.height / 900)))
                let cardWidth = min(420 * scale, geometry.size.width * 0.88)
                let cardHeight = min(compact ? 190 * scale : 230 * scale, geometry.size.height * 0.42)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: compact ? 12 : 24) {
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: (compact ? 42 : 54) * scale, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(context.date.formatted(date: .complete, time: .omitted))
                            .font(.system(size: (compact ? 14 : 17) * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))

                        Button(action: onAuthenticate) {
                            VStack(spacing: compact ? 12 : 18) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: (compact ? 24 : 29) * scale, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Mac is locked")
                                    .font(.system(size: (compact ? 20 : 24) * scale, weight: .semibold))
                                Text("Use Touch ID or password to return.")
                                    .font(.system(size: (compact ? 13 : 15) * scale))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.white)
                            .frame(width: cardWidth, height: cardHeight)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
                                    .strokeBorder(.white.opacity(0.11), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mac is locked. Use Touch ID or password to return.")
                        .accessibilityHint("Starts macOS authentication to return to the Mac.")
                        .accessibilityAddTraits(.isButton)
                        .padding(.top, compact ? 8 : 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                }
            }

            BatteryPercentageIcon(percentage: batteryMonitor.percentage, size: 28, color: .white.opacity(0.78))
                .padding(.top, safeAreaTopInset + 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
