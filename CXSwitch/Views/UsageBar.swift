import SwiftUI

struct UsageBar: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: normalizedPercent)
                .tint(progressColor)
            if let resetText {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var remainingPercent: Double {
        max(0, 100.0 - window.usedPercent)
    }

    private var percentText: String {
        String(format: "%.0f%%", remainingPercent)
    }

    private var normalizedPercent: Double {
        min(max(remainingPercent / 100.0, 0.0), 1.0)
    }

    private var progressColor: Color {
        switch remainingPercent {
        case 40...:
            return .green
        case 15..<40:
            return .orange
        default:
            return .red
        }
    }

    private var resetText: String? {
        if let text = window.resetText, !text.isEmpty {
            return text
        }
        if let remainingSeconds = window.remainingSeconds {
            return formatDuration(seconds: remainingSeconds)
        }
        return nil
    }

    private func formatDuration(seconds: Int) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        if seconds >= 86400 {
            formatter.allowedUnits = [.day, .hour]
        } else if seconds >= 3600 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.minute]
        }
        return formatter.string(from: TimeInterval(seconds))
    }
}
