import CryptoKit
import Foundation
import SwiftData
import UIKit

/// How often NutriLens writes a backup when you open it.
enum BackupFrequency: String, CaseIterable, Identifiable {
    case everyOpen, daily, weekly, off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everyOpen: "Every time I open NutriLens"
        case .daily: "Once a day"
        case .weekly: "Once a week"
        case .off: "Off"
        }
    }
}

/// A backup file name: `NutriLens backup 2026-11-12 iPhone ab12cd34.json`.
/// One file per device per day (a later backup the same day replaces it).
struct BackupFileName: Equatable, Sendable {
    var day: String
    var deviceKind: String
    var deviceID: String

    var fileName: String { "NutriLens backup \(day) \(deviceKind) \(deviceID).json" }

    /// Parses only names NutriLens writes; anything else in the folder is ignored (and never deleted).
    init?(_ fileName: String) {
        let parts = fileName.split(separator: " ")
        guard parts.count == 5, parts[0] == "NutriLens", parts[1] == "backup", parts[4].hasSuffix(".json") else { return nil }
        let day = String(parts[2]), kind = String(parts[3]), id = String(parts[4].dropLast(5))
        let digits = day.split(separator: "-")
        guard digits.count == 3, digits.map(\.count) == [4, 2, 2], digits.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              ["iPhone", "iPad", "Mac", "Device"].contains(kind),
              id.count == 8, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        self.init(day: day, deviceKind: kind, deviceID: id)
    }

    init(day: String, deviceKind: String, deviceID: String) {
        self.day = day
        self.deviceKind = deviceKind
        self.deviceID = deviceID
    }
}

/// Automatic backups to a folder you choose, ideally in iCloud Drive. Each device writes its own dated file;
/// on opening, NutriLens merges the newest file from your other devices first, so the iPhone and iPad keep each
/// other's meals, photos, readings, workouts, custom foods, settings and calendar days. Files in iCloud Drive
/// survive deleting the app: after reinstalling, choose the same folder and the newest backup is merged in.
@MainActor
enum AutoBackup {
    struct ImportResult: Equatable {
        var report = BackupService.ImportReport()
        var settingsChanged = 0
        /// Device kinds merged ("iPad"…).
        var from: [String] = []

        var changedAnything: Bool { report.inserted + report.updated + report.deleted + settingsChanged > 0 }
    }

    enum Failure: LocalizedError {
        case folderUnavailable

        var errorDescription: String? {
            "The backup folder isn't available. Choose it again in Settings › Automatic backup."
        }
    }

    /// Files of this device kept in the folder (older ones are removed).
    static let keepCount = 14

    // MARK: Folder

    /// Remembers `url` (from the folder picker) as the backup folder.
    static func chooseFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: SettingsKey.autoBackupFolder)
        // The top level of "On My iPhone/iPad" reports its internal name.
        let name = url.lastPathComponent == "File Provider Storage" ? "On My \(deviceKind)" : url.lastPathComponent
        defaults.set(name, forKey: SettingsKey.autoBackupFolderName)
        // A new folder: merge whatever is there, and write a fresh backup.
        defaults.removeObject(forKey: SettingsKey.autoBackupImported)
        defaults.removeObject(forKey: SettingsKey.autoBackupLastHash)
        defaults.removeObject(forKey: SettingsKey.autoBackupLastCheck)
    }

    static func forgetFolder(defaults: UserDefaults = .standard) {
        for key in [SettingsKey.autoBackupFolder, SettingsKey.autoBackupFolderName, SettingsKey.autoBackupImported,
                    SettingsKey.autoBackupLastHash, SettingsKey.autoBackupLastCheck] {
            defaults.removeObject(forKey: key)
        }
    }

    static func folderName(defaults: UserDefaults = .standard) -> String? {
        defaults.data(forKey: SettingsKey.autoBackupFolder) == nil ? nil : defaults.string(forKey: SettingsKey.autoBackupFolderName)
    }

    static func frequency(defaults: UserDefaults = .standard) -> BackupFrequency {
        BackupFrequency(rawValue: defaults.string(forKey: SettingsKey.autoBackupFrequency) ?? "") ?? .everyOpen
    }

    /// The chosen folder, refreshing its bookmark if iOS says it's stale.
    static func folderURL(defaults: UserDefaults = .standard) -> URL? {
        guard let bookmark = defaults.data(forKey: SettingsKey.autoBackupFolder) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let accessing = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: SettingsKey.autoBackupFolder)
            }
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    /// This installation's short random ID, made once.
    static func deviceID(defaults: UserDefaults = .standard) -> String {
        DeviceIdentity.id(defaults: defaults)
    }

    static var deviceKind: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .mac: "Mac"
        default: "Device"
        }
    }

    // MARK: Import

    /// Merges the newest backup of each of your other devices that hasn't been merged yet.
    static func importFromFolder(context: ModelContext, defaults: UserDefaults = .standard) async throws -> ImportResult {
        guard frequency(defaults: defaults) != .off, let folder = folderURL(defaults: defaults) else { return ImportResult() }
        let me = deviceID(defaults: defaults)
        let entries = try await FolderIO.run(folder) { try FolderIO.list($0) }
        var imported = defaults.dictionary(forKey: SettingsKey.autoBackupImported) as? [String: Double] ?? [:]

        // Newest file per other device.
        var newest: [String: (name: BackupFileName, entry: FolderIO.Entry)] = [:]
        for entry in entries {
            guard let name = BackupFileName(entry.name), name.deviceID != me else { continue }
            if let current = newest[name.deviceID], current.name.day >= name.day { continue }
            newest[name.deviceID] = (name, entry)
        }

        var result = ImportResult()
        for (_, file) in newest.sorted(by: { $0.value.name.day < $1.value.name.day }) {
            let stamp = file.entry.modified?.timeIntervalSince1970 ?? 0
            if let done = imported[file.entry.name], stamp > 0, done >= stamp { continue }
            let url = file.entry.url
            // A file still downloading from iCloud (or half-written by the other device) is tried again next time.
            guard let data = try? await FolderIO.run(folder, { _ in try FolderIO.read(url) }),
                  let backup = try? BackupService.decode(data) else { continue }
            let report = try BackupService.merge(backup, into: context, applySettings: false, defaults: defaults, replaceNewerDays: false)
            result.report.inserted += report.inserted
            result.report.updated += report.updated
            result.report.deleted += report.deleted
            result.settingsChanged += mergeSettings(backup.settings, defaults: defaults)
            result.from.append(file.name.deviceKind)
            imported[file.entry.name] = stamp > 0 ? stamp : backup.exportedAt.timeIntervalSince1970
        }
        defaults.set(imported, forKey: SettingsKey.autoBackupImported)
        return result
    }

    /// Three-way merge of settings: a setting you haven't changed here since the devices last agreed takes the
    /// other device's value; one you changed here is kept (and goes out in this device's next backup).
    static func mergeSettings(_ incoming: [String: String], defaults: UserDefaults) -> Int {
        var base = defaults.dictionary(forKey: SettingsKey.autoBackupSettingsBase) as? [String: String] ?? [:]
        let current = BackupService.currentSettings(defaults)
        var changed = 0
        for key in BackupService.settingKeys {
            guard let value = incoming[key] else { continue }
            if current[key] == value {
                base[key] = value
            } else if current[key] == base[key] {
                BackupService.applySetting(key, value, defaults: defaults)
                base[key] = value
                changed += 1
            }
        }
        defaults.set(base, forKey: SettingsKey.autoBackupSettingsBase)
        return changed
    }

    // MARK: Write

    /// Writes this device's backup if one is due (per the frequency) and something changed since the last one.
    /// `force` writes regardless. Returns the file name written, or nil if nothing was written.
    @discardableResult
    static func backUpIfDue(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now,
                            calendar: Calendar = .current, force: Bool = false) async throws -> String? {
        let frequency = frequency(defaults: defaults)
        guard force || frequency != .off else { return nil }
        guard let folder = folderURL(defaults: defaults) else {
            if force { throw Failure.folderUnavailable }
            return nil
        }
        if !force, let lastCheck = defaults.object(forKey: SettingsKey.autoBackupLastCheck) as? Double {
            let last = Date(timeIntervalSince1970: lastCheck)
            switch frequency {
            case .daily where calendar.isDate(last, inSameDayAs: now): return nil
            case .weekly where now.timeIntervalSince(last) < 7 * 86_400: return nil
            default: break
            }
        }

        let includePhotos = defaults.object(forKey: SettingsKey.autoBackupPhotos) as? Bool ?? true
        var backup = try BackupService.makeBackup(context: context, includePhotos: includePhotos, defaults: defaults,
                                                  exportedAt: Date(timeIntervalSince1970: 0))
        let hash = SHA256.hash(data: try BackupService.encode(backup)).map { String(format: "%02x", $0) }.joined()
        defaults.set(now.timeIntervalSince1970, forKey: SettingsKey.autoBackupLastCheck)
        if !force, hash == defaults.string(forKey: SettingsKey.autoBackupLastHash) { return nil }

        let me = deviceID(defaults: defaults)
        backup.exportedAt = now
        backup.deviceID = me
        backup.deviceName = deviceKind
        let data = try BackupService.encode(backup)
        let name = BackupFileName(day: DayRecord.key(for: now, calendar: calendar), deviceKind: deviceKind, deviceID: me)
        let keep = keepCount
        try await FolderIO.run(folder) { folder in
            try FolderIO.write(data, to: folder.appendingPathComponent(name.fileName))
            // Keep this device's newest files; never touch anything else in the folder.
            let mine = try FolderIO.list(folder)
                .compactMap { entry in BackupFileName(entry.name).flatMap { $0.deviceID == me ? (entry, $0) : nil } }
                .sorted { $0.1.day > $1.1.day }
            for (entry, _) in mine.dropFirst(keep) { try FolderIO.delete(entry.url) }
        }
        defaults.set(hash, forKey: SettingsKey.autoBackupLastHash)
        defaults.set(now.timeIntervalSince1970, forKey: SettingsKey.autoBackupLastWrite)
        defaults.set(name.fileName, forKey: SettingsKey.autoBackupLastFile)
        defaults.set(BackupService.currentSettings(defaults), forKey: SettingsKey.autoBackupSettingsBase)
        return name.fileName
    }
}

/// Coordinated file access off the main thread (iCloud Drive files may need downloading first).
enum FolderIO {
    struct Entry: Sendable {
        var name: String
        var url: URL
        var modified: Date?
    }

    /// Runs `body` on a background thread with access to the security-scoped `folder`.
    static func run<T: Sendable>(_ folder: URL, _ body: @escaping @Sendable (URL) throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            return try body(folder)
        }.value
    }

    /// Files in the folder. iCloud Drive files not yet on this device (".name.json.icloud") are listed under their
    /// real names and asked to download.
    static func list(_ folder: URL) throws -> [Entry] {
        var result: [Entry] = []
        var coordinationError: NSError?
        var listError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
                for item in urls {
                    var name = item.lastPathComponent
                    if name.hasPrefix("."), name.hasSuffix(".icloud") {
                        name = String(name.dropFirst().dropLast(7))
                        let real = folder.appendingPathComponent(name)
                        try? FileManager.default.startDownloadingUbiquitousItem(at: real)
                        result.append(Entry(name: name, url: real, modified: nil))
                    } else {
                        let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                        result.append(Entry(name: name, url: folder.appendingPathComponent(name), modified: modified))
                    }
                }
            } catch {
                listError = error
            }
        }
        if let error = coordinationError ?? listError { throw error }
        return result
    }

    /// Reads a file, waiting for iCloud Drive to download it if needed.
    static func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func write(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    static func delete(_ url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
