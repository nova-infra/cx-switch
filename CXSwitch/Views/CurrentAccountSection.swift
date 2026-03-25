import SwiftUI

struct CurrentAccountSection: View {
    let account: Account?
    let preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.currentAccount)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let account {
                            Text(displayEmail(for: account))
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(Strings.noActiveAccount)
                                .font(.headline.weight(.semibold))
                                .lineLimit(2)
                        }

                        if let account {
                            HStack(spacing: 4) {
                                if let accountType = account.accountType {
                                    infoText(accountType.displayName)
                                }

                                if let planType = account.planType {
                                    infoText(Strings.planTypeDisplayName(for: planType))
                                }
                            }
                        }

                        Spacer(minLength: 8)
                    }
                }
            }

            if let account {
                if let snapshot = account.usageSnapshot {
                    usageBars(primary: snapshot.primary, secondary: snapshot.secondary)
                }

                if let error = account.usageError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .adaptiveGlass()
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
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBar(window: window, style: .compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if let window = windows.first {
            UsageBar(window: window, style: .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }

}
