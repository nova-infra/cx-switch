import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @State private var showImportToken = false
    @State private var importToken = ""

    var body: some View {
        mainPanel
            .padding(16)
            .fixedSize(horizontal: false, vertical: true)
        .frame(width: 360)
        .task(id: "init") {
            await state.loadDashboard()
        }
        .sheet(isPresented: loginFlowBinding) {
            LoginFlowSheet(
                loginFlow: state.loginFlow,
                onCancel: { Task { await state.cancelAddAccount() } }
            )
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            CurrentAccountSection(
                account: state.currentAccount,
                preferences: state.preferences,
                refreshing: state.isRefreshing(accountID: state.currentAccount?.id),
                onRefresh: { Task { await state.refreshCurrentAccount() } }
            )

            let currentId = state.currentAccount?.id
            let otherAccounts = state.savedAccounts.filter { $0.id != currentId }
            if !otherAccounts.isEmpty {
                sectionDivider

                VStack(alignment: .leading, spacing: 10) {
                    Text(Strings.switchTo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(otherAccounts) { account in
                        SavedAccountRow(
                            account: account,
                            preferences: state.preferences,
                            onSelect: { Task { await state.switchAccount(to: account) } },
                            onRefresh: { Task { await state.refreshAccount(account) } },
                            refreshing: state.isRefreshing(accountID: account.id)
                        )
                    }
                }
            }

            sectionDivider

            FooterActions(
                maskEmails: state.preferences.maskEmails ?? false,
                onAddAccount: { Task { await state.startAddAccount() } },
                onImportToken: { toggleImportToken() },
                onToggleMaskEmails: { state.setMaskEmails(!(state.preferences.maskEmails ?? false)) },
                onOpenSettings: { state.openSettings() },
                onOpenStatus: { state.openStatusPage() },
                onQuit: { state.quit() }
            )

            if showImportToken {
                HStack(spacing: 6) {
                    TextField(Strings.importTokenPlaceholder, text: $importToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { doImport() }
                    Button(action: doImport) {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(importToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if state.refreshing || messageText != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if state.refreshing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(refreshingMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let messageText {
                        Text(messageText)
                            .font(.caption)
                            .foregroundStyle(messageColor)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var loginFlowBinding: Binding<Bool> {
        Binding(
            get: { state.loginFlow.active },
            set: { isPresented in
                if !isPresented {
                    Task { await state.cancelAddAccount() }
                }
            }
        )
    }

    @ViewBuilder
    private var sectionDivider: some View {
        Divider()
            .opacity(0.35)
    }

    private var messageText: String? {
        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if let statusMessage = state.statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        return nil
    }

    private var messageColor: Color {
        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            return .red
        }
        return .green
    }

    private var refreshingMessage: String {
        if let label = state.refreshingAccountLabel(), !label.isEmpty {
            return Strings.L("正在刷新 \(label)…", en: "Refreshing \(label)...")
        }
        return Strings.L("正在刷新…", en: "Refreshing...")
    }

    private func doImport() {
        let token = importToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        importToken = ""
        showImportToken = false
        Task { await state.importRefreshToken(token) }
    }

    private func toggleImportToken() {
        showImportToken.toggle()
    }
}
