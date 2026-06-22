import Foundation

enum AcknowledgmentStatus: String, Codable, Sendable {
    case pending
    case acknowledged
    case expired
}

struct AcknowledgmentRecord: Codable, Identifiable, Sendable {
    var id: String { key.storageKey }
    let key: EventKey
    var status: AcknowledgmentStatus
    let createdAt: Date
}

@Observable
final class AcknowledgmentStore {
    private(set) var records: [AcknowledgmentRecord] = []

    init() {
        load()
    }

    var pendingRecords: [AcknowledgmentRecord] {
        records.filter { $0.status == .pending && !isExpired($0) }
    }

    /// Oldest started event still awaiting acknowledgment.
    var primaryPendingRecord: AcknowledgmentRecord? {
        pendingRecords.min { $0.key.startDate < $1.key.startDate }
    }

    func canMarkPending(for key: EventKey) -> Bool {
        guard let primary = primaryPendingRecord else { return true }
        return primary.key.matches(snapshot: key) || primary.key.storageKey == key.storageKey
    }

    func load() {
        guard
            let data = UserDefaults.standard.data(forKey: AppConstants.ackStoreKey),
            let decoded = try? JSONDecoder().decode([AcknowledgmentRecord].self, from: data)
        else {
            records = []
            return
        }
        records = decoded
        normalizePendingToSingle()
    }

    /// Keep at most one pending acknowledgment; drop extras so they can fire again later.
    func normalizePendingToSingle() {
        let pending = pendingRecords.sorted { $0.key.startDate < $1.key.startDate }
        guard pending.count > 1 else { return }
        let keepID = pending[0].id
        records.removeAll { $0.status == .pending && $0.id != keepID }
        save()
    }

    func save() {
        let data = try? JSONEncoder().encode(records)
        UserDefaults.standard.set(data, forKey: AppConstants.ackStoreKey)
    }

    func record(for key: EventKey) -> AcknowledgmentRecord? {
        records.first { $0.key.matches(snapshot: key) || $0.key.storageKey == key.storageKey }
    }

    func isPending(_ key: EventKey) -> Bool {
        guard let record = record(for: key) else { return false }
        return record.status == .pending && !isExpired(record)
    }

    func markPending(_ key: EventKey) {
        guard canMarkPending(for: key) else { return }
        if var existing = record(for: key) {
            existing.status = .pending
            replace(existing)
        } else {
            records.append(AcknowledgmentRecord(key: key, status: .pending, createdAt: Date()))
        }
        save()
    }

    func markAcknowledged(_ key: EventKey) {
        updateStatus(key, to: .acknowledged)
    }

    func markExpired(_ key: EventKey) {
        updateStatus(key, to: .expired)
    }

    func pruneAcknowledgedAndExpired() {
        records.removeAll { $0.status == .acknowledged || $0.status == .expired || isExpired($0) }
        save()
    }

    func isExpired(_ record: AcknowledgmentRecord) -> Bool {
        Date().timeIntervalSince(record.key.startDate) >= AppConstants.ackWindowSeconds
    }

    private func updateStatus(_ key: EventKey, to status: AcknowledgmentStatus) {
        if var existing = record(for: key) {
            existing.status = status
            replace(existing)
        } else {
            records.append(AcknowledgmentRecord(key: key, status: status, createdAt: Date()))
        }
        save()
    }

    private func replace(_ record: AcknowledgmentRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else if let index = records.firstIndex(where: { $0.key.matches(snapshot: record.key) }) {
            records[index] = record
        }
    }
}
