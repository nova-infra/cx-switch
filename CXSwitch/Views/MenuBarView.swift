import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showImportToken = false
    @State private var importToken = ""

    var body: some View {
        ScrollView(.vertical) {
            activePanel
                .padding(16)
                .frame(width: 360, alignment: .leading)
        }
        .frame(width: 360)
        .frame(maxHeight: 560)
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
    private var activePanel: some View {
        if showSettings {
            SettingsView(onBack: { showSettings = false })
        } else {
            mainPanel
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
            let allAccounts = state.savedAccounts
            if !allAccounts.isEmpty {
                sectionDivider

                VStack(alignment: .leading, spacing: 10) {
                    Text(Strings.switchTo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(allAccounts) { account in
                        SavedAccountRow(
                            account: account,
                            preferences: state.preferences,
                            isCurrent: account.id == currentId,
                            onSelect: { selectAccount(account) },
                            onRefresh: { Task { await state.refreshAccount(account) } },
                            refreshing: state.isRefreshing(accountID: account.id),
                            switching: state.switchingAccountID == account.id
                        )
                    }
                }
            }

            sectionDivider

            FooterActions(
                onAddAccount: { Task { await state.startAddAccount() } },
                onImportToken: { toggleImportToken() },
                onOpenSettings: { showSettings = true },
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

            if let activity = activityMessage {
                activityStrip(text: activity, color: activityColor, showSpinner: showActivitySpinner)
                    .padding(.top, 4)
            }
        }
        .animation(.snappy(duration: 0.2), value: state.switchingAccountID)
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

    private var activityMessage: String? {
        if let messageText {
            return messageText
        }
        if state.refreshing {
            return refreshingMessage
        }
        return nil
    }

    private var activityColor: Color {
        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            return .red
        }
        if state.refreshing {
            return .secondary
        }
        return .green
    }

    private var showActivitySpinner: Bool {
        state.refreshing && (state.errorMessage?.isEmpty ?? true)
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

    private func selectAccount(_ account: Account) {
        Task {
            await state.switchAccount(to: account)
        }
    }

    private func activityStrip(text: String, color: Color, showSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
