import SwiftUI

struct UsageBar: View {
    enum Style {
        case regular
        case compact
    }

    let window: UsageWindow
    var style: Style = .regular

    var body: some View {
        switch style {
        case .regular:
            regularBody
        case .compact:
            compactBody
        }
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Spacer()
                Text(percentText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: normalizedPercent)
                .tint(progressColor)
            HStack(spacing: 6) {
                Text(displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let resetText {
                    Text(resetText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ProgressView(value: normalizedPercent)
                    .tint(progressColor)
                    .controlSize(.small)

                Text(percentText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text(displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let resetText {
                    Text(resetText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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

    private var compactLabel: String {
        switch window.label.lowercased() {
        case "5 hours":
            return "5h"
        case "weekly":
            return "week"
        default:
            return window.label
        }
    }

    private var displayLabel: String {
        compactLabel
    }
}
