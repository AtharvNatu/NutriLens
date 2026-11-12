import Foundation
import SwiftData

/// A short id for this install ("3f9c0a1b"), used to name backup files and to stamp records this device creates.
enum DeviceIdentity {
    static func id(defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: SettingsKey.deviceID), id.count == 8 { return id }
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        defaults.set(id, forKey: SettingsKey.deviceID)
        return id
    }
}

/// Removes duplicate copies of the same record that iCloud sync can leave behind.
///
/// Duplicates appear when both devices already held the same meals (from the earlier Apple Health or backup
/// sync) and each uploads its own copy, or when an import adds a record that iCloud then delivers too.
/// Copies share the record's `id` (or `dayKey` for day records).
///
/// Both devices run this, so they must agree on which copy to keep, or each could delete the other's and lose
/// the record. The kept copy is the newest edit; between equally new copies, the one stamped by the device with
/// the smaller id. A group is left alone while any copy is unstamped (its stamp is still on the way), and copies
/// from the same device are only resolved by that device.
@MainActor
enum CloudDeduplicator {
    struct Copy {
        var key: String
        var updatedAt: Date
        var origin: String
    }

    /// Indices of the copies to delete, or [] when this device shouldn't decide yet.
    static func doomed(_ copies: [Copy], device: String) -> [Int] {
        guard copies.count > 1, !copies.contains(where: { $0.origin.isEmpty }) else { return [] }
        let order = copies.indices.sorted { a, b in
            let x = copies[a], y = copies[b]
            if x.updatedAt != y.updatedAt { return x.updatedAt > y.updatedAt }
            return x.origin < y.origin
        }
        let keep = copies[order[0]]
        let tied = order.dropFirst().filter { copies[$0].updatedAt == keep.updatedAt && copies[$0].origin == keep.origin }
        // Copies made on one device look the same everywhere: only that device picks between them.
        if !tied.isEmpty && keep.origin != device { return [] }
        return Array(order.dropFirst())
    }

    /// Gives records made before iCloud sync this device's stamp. Run once, at the first launch with iCloud sync,
    /// before anything arrives from the other device.
    static func stampUnclaimed(context: ModelContext, device: String) {
        func stamp<T: PersistentModel>(_ type: T.Type, _ origin: ReferenceWritableKeyPath<T, String>) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] where item[keyPath: origin].isEmpty {
                item[keyPath: origin] = device
            }
        }
        stamp(MealEntry.self, \.originDevice)
        stamp(BodyMeasurement.self, \.originDevice)
        stamp(WorkoutLog.self, \.originDevice)
        stamp(CustomFood.self, \.originDevice)
        stamp(DeletedRecord.self, \.originDevice)
        stamp(DayRecord.self, \.originDevice)
        try? context.save()
    }

    /// Deletes duplicates; returns how many copies were removed.
    @discardableResult
    static func run(context: ModelContext, device: String) -> Int {
        var removed = 0
        func dedupe<T: PersistentModel>(_ type: T.Type, key: (T) -> String, updatedAt: (T) -> Date, origin: (T) -> String) {
            let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for group in Dictionary(grouping: items, by: key).values where group.count > 1 {
                let copies = group.map { Copy(key: key($0), updatedAt: updatedAt($0), origin: origin($0)) }
                for index in doomed(copies, device: device) {
                    context.delete(group[index])
                    removed += 1
                }
            }
        }
        dedupe(MealEntry.self, key: { $0.id.uuidString }, updatedAt: { $0.updatedAt }, origin: { $0.originDevice })
        dedupe(BodyMeasurement.self, key: { $0.id.uuidString }, updatedAt: { $0.updatedAt }, origin: { $0.originDevice })
        dedupe(WorkoutLog.self, key: { $0.id.uuidString }, updatedAt: { $0.updatedAt }, origin: { $0.originDevice })
        dedupe(CustomFood.self, key: { $0.id.uuidString }, updatedAt: { $0.updatedAt }, origin: { $0.originDevice })
        dedupe(DeletedRecord.self, key: { $0.id.uuidString }, updatedAt: { $0.deletedAt }, origin: { $0.originDevice })
        dedupe(DayRecord.self, key: { $0.dayKey }, updatedAt: { $0.updatedAt }, origin: { $0.originDevice })
        if removed > 0 { try? context.save() }
        return removed
    }
}

/// Where synced settings are kept: iCloud key-value storage in the app, a plain dictionary in tests.
protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsStore {
    func set(_ value: String?, forKey key: String) {
        if let value { set(value as Any?, forKey: key) } else { removeObject(forKey: key) }
    }
}

/// Keeps your settings (targets, profile, plan start, usual recipe amounts…) the same on iPhone and iPad through
/// iCloud key-value storage. Only `BackupService.settingKeys` travel; device-only state (backup folder, sync
/// times) stays put.
///
/// A snapshot of the last values both sides agreed on tells which side changed a key. When both changed the same
/// key before syncing, the other device's value wins.
@MainActor
final class SettingsCloudSync {
    static let snapshotKey = "settingsCloudSnapshot"
    private let store: SettingsStore
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var pushTask: Task<Void, Never>?

    init(store: SettingsStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    private var snapshot: [String: String] {
        get {
            guard let data = defaults.string(forKey: Self.snapshotKey)?.data(using: .utf8),
                  let value = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return value
        }
        set {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(newValue) { defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.snapshotKey) }
        }
    }

    /// Applies keys the other device changed. Returns how many settings changed here.
    @discardableResult
    func pull() -> Int {
        var known = snapshot
        var changed = 0
        for key in BackupService.settingKeys {
            guard let remote = store.string(forKey: key), remote != known[key] else { continue }
            if BackupService.currentSettings(defaults)[key] != remote {
                BackupService.applySetting(key, remote, defaults: defaults)
                changed += 1
            }
            known[key] = remote
        }
        if known != snapshot { snapshot = known }
        return changed
    }

    /// Sends keys changed here. Returns how many were sent.
    @discardableResult
    func push() -> Int {
        var known = snapshot
        let local = BackupService.currentSettings(defaults)
        var sent = 0
        for key in BackupService.settingKeys {
            guard let value = local[key], value != known[key] else { continue }
            store.set(value, forKey: key)
            known[key] = value
            sent += 1
        }
        if sent > 0 {
            snapshot = known
            store.synchronize()
        }
        return sent
    }

    /// Pulls, then pushes, now and whenever either side changes.
    func start(onChange: @escaping @MainActor () -> Void) {
        store.synchronize()
        if pull() > 0 { onChange() }
        push()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                            object: store as? NSUbiquitousKeyValueStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.pull() ?? 0 > 0 { onChange() }
            }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePush() }
        })
    }

    /// Settings sliders change many times a second; send once they settle.
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }
}
