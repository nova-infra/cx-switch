import SwiftUI

struct FooterActions: View {
    let onAddAccount: () -> Void
    let onRefreshAll: () -> Void
    let onImportToken: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let isRefreshing: Bool

    var body: some View {
        AdaptiveGlassContainer {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                actionCell(
                    title: Strings.L("Refresh All", en: "Refresh All"),
                    systemImage: "arrow.clockwise",
                    isLoading: isRefreshing
                ) {
                    onRefreshAll()
                }

                actionCell(
                    title: Strings.addAccount,
                    systemImage: "plus"
                ) {
                    onAddAccount()
                }

                actionCell(
                    title: Strings.importToken,
                    systemImage: "arrow.down.circle"
                ) {
                    onImportToken()
                }

                actionCell(
                    title: Strings.settings,
                    systemImage: "gearshape"
                ) {
                    onOpenSettings()
                }

                actionCell(
                    title: Strings.quit,
                    systemImage: "power"
                ) {
                    onQuit()
                }
            }
        }
    }

    @ViewBuilder
    private func actionCell(title: String, systemImage: String, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
