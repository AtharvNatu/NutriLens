import Foundation

/// Version information for one record, used to merge data between devices.
public struct SyncStamp: Codable, Hashable, Sendable {
    public var id: UUID
    public var updatedAt: Date
    public var deleted: Bool

    public init(id: UUID, updatedAt: Date, deleted: Bool = false) {
        self.id = id
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

public enum SyncAction: Equatable, Sendable {
    case insert(UUID)
    case update(UUID)
    case delete(UUID)
}

/// Last-writer-wins merge of an incoming set of records into the local set.
///
/// Deletions travel as tombstones (`deleted == true`) so that removing something on the iPhone also
/// removes it on the iPad. A record changed after it was deleted elsewhere comes back (newer wins).
public enum SyncMerge {
    public static func actions(local: [SyncStamp], incoming: [SyncStamp]) -> [SyncAction] {
        var localByID: [UUID: SyncStamp] = [:]
        for stamp in local {
            if let existing = localByID[stamp.id], existing.updatedAt >= stamp.updatedAt { continue }
            localByID[stamp.id] = stamp
        }
        var result: [SyncAction] = []
        var seen = Set<UUID>()
        for remote in incoming.sorted(by: { $0.updatedAt > $1.updatedAt }) where seen.insert(remote.id).inserted {
            if let mine = localByID[remote.id] {
                guard remote.updatedAt > mine.updatedAt else { continue }
                if remote.deleted {
                    if !mine.deleted { result.append(.delete(remote.id)) }
                } else {
                    result.append(mine.deleted ? .insert(remote.id) : .update(remote.id))
                }
            } else if !remote.deleted {
                result.append(.insert(remote.id))
            }
        }
        return result
    }
}
