import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @State private var showImportToken = false
    @State private var showSettings = false
    @State private var importToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .padding(12)
        .frame(width: 320)
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
        CurrentAccountSection(
            account: state.currentAccount,
            preferences: state.preferences
        )

        let currentId = state.currentAccount?.id
        let otherAccounts = state.savedAccounts.filter { $0.id != currentId }
        if !otherAccounts.isEmpty {
            Text(Strings.switchTo)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(otherAccounts) { account in
                SavedAccountRow(
                    account: account,
                    preferences: state.preferences,
                    onSelect: { Task { await state.switchAccount(to: account) } }
                )
            }
        }

        HStack(spacing: 8) {
            Button(Strings.addAccount) {
                Task { await state.startAddAccount() }
            }
            Button(Strings.importToken) {
                showImportToken.toggle()
            }
            Button(Strings.refresh) {
                Task { await state.refreshSavedAccounts(force: true) }
            }
        }

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

        if state.refreshing {
            ProgressView()
                .controlSize(.small)
        }

        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Divider()

        FooterActions(
            onOpenSettings: { showSettings = true },
            onOpenStatus: { state.openStatusPage() },
            onQuit: { state.quit() }
        )
    }

    @ViewBuilder
    private var settingsPanel: some View {
        HStack {
            Button(action: { showSettings = false }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Text(Strings.settings)
                .font(.headline)
            Spacer()
        }

        Divider()

        Toggle(Strings.saveToKeychain, isOn: Binding(
            get: { state.preferences.saveToKeychain ?? false },
            set: { state.setSaveToKeychain($0) }
        ))
        .font(.subheadline)

        Toggle(Strings.maskEmails, isOn: Binding(
            get: { state.preferences.maskEmails ?? false },
            set: { state.setMaskEmails($0) }
        ))
        .font(.subheadline)

        Divider()

        Button(action: { state.openSettings() }) {
            HStack {
                Image(systemName: "folder")
                Text(Strings.openDataFolder)
                    .font(.subheadline)
            }
        }
        .buttonStyle(.plain)
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

    private func doImport() {
        let token = importToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        importToken = ""
        showImportToken = false
        Task { await state.importRefreshToken(token) }
    }
}

