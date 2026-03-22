import SwiftUI

struct SavedAccountRow: View {
    let account: Account
    let preferences: Preferences
    let isCurrent: Bool
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let refreshing: Bool
    let switching: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayEmail(for: account))
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let accountType = account.accountType {
                            infoText(accountType.displayName)
                        }

                        if let planType = account.planType {
                            infoText(Strings.planTypeDisplayName(for: planType))
                        }

                        if isCurrent {
                            infoText(Strings.L("当前", en: "Current"))
                        }

                        Spacer(minLength: 8)
                    }

                    if let usageSnapshot = account.usageSnapshot {
                        usageBars(primary: usageSnapshot.primary, secondary: usageSnapshot.secondary)
                    }

                    if let error = account.usageError, !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayEmail(for: account))

            HStack(spacing: 6) {
                if switching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .transition(.opacity)
                }

                Button(action: onRefresh) {
                    Group {
                        if refreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(refreshing)
                .accessibilityLabel(Strings.refresh)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(switching ? 0.05 : 0.001))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(switching ? 0.08 : 0.0))
        )
        .animation(.snappy(duration: 0.2), value: switching)
    }

    private func displayEmail(for account: Account) -> String {
        if preferences.maskEmails ?? false {
            return account.maskedEmail
        }
        return account.email
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func usageBars(primary: UsageWindow?, secondary: UsageWindow?) -> some View {
        let windows = [primary, secondary].compactMap { $0 }

        if windows.count == 2 {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBar(window: window, style: .compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if let window = windows.first {
            UsageBar(window: window, style: .compact)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
