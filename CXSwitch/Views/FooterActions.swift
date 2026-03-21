import SwiftUI

struct FooterActions: View {
    let maskEmails: Bool
    let onAddAccount: () -> Void
    let onImportToken: () -> Void
    let onToggleMaskEmails: () -> Void
    let onOpenSettings: () -> Void
    let onOpenStatus: () -> Void
    let onQuit: () -> Void

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            alignment: .leading,
            spacing: 8
        ) {
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
                title: Strings.status,
                systemImage: "waveform.path.ecg"
            ) {
                onOpenStatus()
            }

            actionCell(
                title: maskEmails ? Strings.L("显示邮箱", en: "Show Emails") : Strings.maskEmails,
                systemImage: maskEmails ? "eye" : "eye.slash"
            ) {
                onToggleMaskEmails()
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

    @ViewBuilder
    private func actionCell(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }
}
