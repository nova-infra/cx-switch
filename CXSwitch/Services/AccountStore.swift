import Foundation

enum AccountStoreError: Error {
    case invalidDirectory
    case readFailed
    case writeFailed
}

final class AccountStore {
    private let fileManager: FileManager
    private let appSupportURL: URL
    private let codexAuthURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL? = nil,
        codexAuthURL: URL? = nil
    ) throws {
        self.fileManager = fileManager

        if let appSupportURL {
            self.appSupportURL = appSupportURL
        } else {
            guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw AccountStoreError.invalidDirectory
            }
            self.appSupportURL = base.appendingPathComponent("com.novainfra.cx-switch", isDirectory: true)
        }

        if let codexAuthURL {
            self.codexAuthURL = codexAuthURL
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.codexAuthURL = home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadPreferences() throws -> Preferences {
        let url = preferencesURL
        guard fileManager.fileExists(atPath: url.path) else {
            return Preferences()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Preferences.self, from: data)
    }

    func savePreferences(_ preferences: Preferences) throws {
        try ensureAppSupportDirectory()
        let data = try encoder.encode(preferences)
        try writeAtomically(data: data, to: preferencesURL)
    }

    func readAuthFile() throws -> AuthBlob? {
        guard fileManager.fileExists(atPath: codexAuthURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: codexAuthURL)
        return try decoder.decode(AuthBlob.self, from: data)
    }

    func writeAuthFile(_ blob: AuthBlob) throws {
        let directory = codexAuthURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(blob)
        try writeAtomically(data: data, to: codexAuthURL)
    }

    private var registryURL: URL {
        appSupportURL.appendingPathComponent("registry.json", isDirectory: false)
    }

    private var preferencesURL: URL {
        appSupportURL.appendingPathComponent("preferences.json", isDirectory: false)
    }

    private func ensureAppSupportDirectory() throws {
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func writeAtomically(data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw AccountStoreError.writeFailed
        }
    }

    var appSupportDirectoryURL: URL {
        appSupportURL
    }

    var registryFileURL: URL {
        registryURL
    }

    var migratedRegistryFileURL: URL {
        appSupportURL.appendingPathComponent("registry.json.migrated", isDirectory: false)
    }

    func archiveRegistryForMigration() throws {
        guard fileManager.fileExists(atPath: registryURL.path) else { return }
        try ensureAppSupportDirectory()

        if fileManager.fileExists(atPath: migratedRegistryFileURL.path) {
            try fileManager.removeItem(at: migratedRegistryFileURL)
        }
        try fileManager.moveItem(at: registryURL, to: migratedRegistryFileURL)
    }
}
