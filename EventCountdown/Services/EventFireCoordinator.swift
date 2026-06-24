import Foundation

final class EventFireCoordinator {
    private var firedKeys: Set<String> = []
    private let lock = NSLock()

    func hasFired(_ key: EventKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return firedKeys.contains(key.storageKey)
    }

    @discardableResult
    func fireIfNeeded(_ key: EventKey, action: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !firedKeys.contains(key.storageKey) else { return false }
        firedKeys.insert(key.storageKey)
        action()
        return true
    }

    func markFired(_ key: EventKey) {
        lock.lock()
        defer { lock.unlock() }
        firedKeys.insert(key.storageKey)
    }

    func reset(_ key: EventKey) {
        lock.lock()
        defer { lock.unlock() }
        firedKeys.remove(key.storageKey)
    }

    func seedFiredKeys(from store: AcknowledgmentStore) {
        lock.lock()
        defer { lock.unlock() }
        for record in store.records where record.status != .pending {
            firedKeys.insert(record.key.storageKey)
        }
        for record in store.pendingRecords {
            firedKeys.insert(record.key.storageKey)
        }
    }
}
