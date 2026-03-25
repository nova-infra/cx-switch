import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @EnvironmentObject private var updaterService: UpdaterService
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: maskEmailsBinding) {
                    Text(Strings.maskEmails)
                        .font(.body)
                }

                pickerSection(
                    title: Strings.language,
                    selection: languageBinding,
                    options: [
                        (Strings.languageChinese, "zh"),
                        (Strings.languageEnglish, "en")
                    ]
                )

                pickerSection(
                    title: Strings.theme,
                    selection: themeBinding,
                    options: [
                        (Strings.themeSystem, "system"),
                        (Strings.themeLight, "light"),
                        (Strings.themeDark, "dark")
                    ]
                )
            }
            .padding(14)
            .adaptiveGlass()

            Divider()
                .opacity(0.35)

            VStack(spacing: 8) {
                actionRow(
                    title: Strings.openaiStatus,
                    systemImage: "safari",
                    action: state.openStatusPage
                )

                actionRow(
                    title: Strings.openDataFolder,
                    systemImage: "folder",
                    action: state.openSettings
                )
            }

            Divider()
                .opacity(0.35)

            versionSection
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Strings.version) \(AppState.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if updaterService.isAvailable {
                Button(action: { updaterService.checkForUpdates() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .center)

                        Text(Strings.checkForUpdates)
                            .font(.body)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .disabled(!updaterService.canCheckForUpdates)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.L("返回", en: "Back"))

            Text(Strings.settings)
                .font(.title3.weight(.semibold))

            Spacer()
        }
    }

    private func pickerSection(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].0).tag(options[index].1)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func actionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(.body)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var maskEmailsBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.maskEmails ?? false },
            set: { state.setMaskEmails($0) }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { state.preferences.language },
            set: { state.setLanguage($0) }
        )
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { normalizedTheme(state.preferences.theme) },
            set: { state.setTheme($0) }
        )
    }

    private func normalizedTheme(_ value: String?) -> String {
        switch value?.lowercased() {
        case "light", "dark":
            return value?.lowercased() ?? Preferences.defaultTheme
        case "system":
            return "system"
        default:
            return Preferences.defaultTheme
        }
    }
}
