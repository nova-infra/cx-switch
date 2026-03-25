import AppKit
import SwiftUI

struct MenuBarView: View {
    private let scrollCoordinateSpace = "MenuBarScroll"

    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showImportToken = false
    @State private var importToken = ""
    @State private var contentHeight: CGFloat = 300
    @State private var topAnchorY: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topAnchor
                activePanel
                bottomAnchor
            }
            .padding(16)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .coordinateSpace(name: scrollCoordinateSpace)
        .frame(width: 360, height: min(contentHeight, screenHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            if height > 0 {
                contentHeight = height
            }
        }
        .onPreferenceChange(ScrollPositionKey.self) { position in
            if let topAnchorY = position.topAnchorY {
                self.topAnchorY = topAnchorY
            }
            if let bottomAnchorY = position.bottomAnchorY {
                self.bottomAnchorY = bottomAnchorY
            }
        }
        .overlay(alignment: .top) {
            if showsUpArrow {
                scrollArrow(direction: .up)
            }
        }
        .overlay(alignment: .bottom) {
            if showsDownArrow {
                scrollArrow(direction: .down)
            }
        }
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

    private var showsScrollableArrows: Bool {
        contentHeight > screenHeight
    }

    private var showsUpArrow: Bool {
        showsScrollableArrows && topAnchorY < 0
    }

    private var showsDownArrow: Bool {
        showsScrollableArrows && bottomAnchorY > min(contentHeight, screenHeight)
    }

    private var screenHeight: CGFloat {
        NSScreen.main?.visibleFrame.height ?? 600
    }

    @ViewBuilder
    private var topAnchor: some View {
        Color.clear
            .frame(height: 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollPositionKey.self,
                        value: ScrollPosition(
                            topAnchorY: proxy.frame(in: .named(scrollCoordinateSpace)).minY
                        )
                    )
                }
            }
    }

    @ViewBuilder
    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollPositionKey.self,
                        value: ScrollPosition(
                            bottomAnchorY: proxy.frame(in: .named(scrollCoordinateSpace)).maxY
                        )
                    )
                }
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
                preferences: state.preferences
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
                            isCurrent: false,
                            onSelect: { selectAccount(account) },
                            switching: state.switchingAccountID == account.id
                        )
                    }
                }
            }

            sectionDivider

            FooterActions(
                onAddAccount: { Task { await state.startAddAccount() } },
                onRefreshAll: { Task { await state.refreshAllAccounts() } },
                onImportToken: { toggleImportToken() },
                onOpenSettings: { showSettings = true },
                onQuit: { state.quit() },
                isRefreshing: state.refreshing
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

    private func scrollArrow(direction: ArrowDirection) -> some View {
        HStack {
            Spacer()
            Image(systemName: direction == .up ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 20)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0)
                ],
                startPoint: direction == .up ? .top : .bottom,
                endPoint: direction == .up ? .bottom : .top
            )
        )
        .allowsHitTesting(false)
    }
}

private enum ArrowDirection {
    case up
    case down
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScrollPosition: Equatable {
    var topAnchorY: CGFloat?
    var bottomAnchorY: CGFloat?

    init(topAnchorY: CGFloat? = nil, bottomAnchorY: CGFloat? = nil) {
        self.topAnchorY = topAnchorY
        self.bottomAnchorY = bottomAnchorY
    }
}

private struct ScrollPositionKey: PreferenceKey {
    static let defaultValue = ScrollPosition()

    static func reduce(value: inout ScrollPosition, nextValue: () -> ScrollPosition) {
        let nextValue = nextValue()
        if let topAnchorY = nextValue.topAnchorY {
            value.topAnchorY = topAnchorY
        }
        if let bottomAnchorY = nextValue.bottomAnchorY {
            value.bottomAnchorY = bottomAnchorY
        }
    }
}
