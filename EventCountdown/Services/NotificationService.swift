import AppKit
import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onAcknowledge: ((String) -> Void)?
    var onExpire: ((String) -> Void)?
    var onDelivered: ((String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        handlePayload(notification.request.content.userInfo)
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == "ACKNOWLEDGE" {
            if let key = userInfo["eventKey"] as? String {
                onAcknowledge?(key)
            }
        } else if response.actionIdentifier == "JOIN_CALL" {
            if let urlString = userInfo["callURL"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            if let key = userInfo["eventKey"] as? String {
                onAcknowledge?(key)
            }
        } else {
            handlePayload(userInfo)
        }
    }

    private func handlePayload(_ userInfo: [AnyHashable: Any]) {
        if let action = userInfo["action"] as? String, action == "expire",
           let key = userInfo["eventKey"] as? String {
            onExpire?(key)
        } else if let key = userInfo["eventKey"] as? String {
            onDelivered?(key)
        }
    }
}

@Observable
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private let coordinator = EventFireCoordinator()
    private let ackStore: AcknowledgmentStore

    var onAcknowledged: ((EventKey) async -> Void)?

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: AppConstants.notificationsEnabledKey) }
    }

    private(set) var permissionGranted = false

    init(ackStore: AcknowledgmentStore) {
        self.ackStore = ackStore
        isEnabled = UserDefaults.standard.object(forKey: AppConstants.notificationsEnabledKey) as? Bool ?? true
        center.delegate = delegate
        wireDelegate()
        coordinator.seedFiredKeys(from: ackStore)
    }

    func start() {
        Task { await requestPermission() }
    }

    func requestPermission() async {
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        permissionGranted = granted ?? false
        await registerCategories()
    }

    func restoreOnLaunch(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        ackStore.normalizePendingToSingle()
        for record in ackStore.records {
            switch record.status {
            case .acknowledged, .expired:
                await removeNotifications(for: record.key)
            case .pending:
                if ackStore.isExpired(record) {
                    ackStore.markExpired(record.key)
                    await removeNotifications(for: record.key)
                }
            }
        }
        ackStore.pruneAcknowledgedAndExpired()
        if isEnabled {
            await scheduleUpcoming(events: events, emojiProvider: emojiProvider)
        }
        await cleanupOrphans(events: events)
    }

    func scheduleUpcoming(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        guard isEnabled else { return }

        let pendingRequests = await center.pendingNotificationRequests()
        let scheduledIDs = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(AppConstants.notificationPrefix) }

        if ackStore.primaryPendingRecord != nil {
            center.removePendingNotificationRequests(withIdentifiers: scheduledIDs)
            return
        }

        guard let nextEvent = nextSchedulableEvent(in: events) else {
            center.removePendingNotificationRequests(withIdentifiers: scheduledIDs)
            return
        }

        let keepID = nextEvent.eventKey.notificationID
        let stale = scheduledIDs.filter { $0 != keepID }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard !pendingRequests.contains(where: { $0.identifier == keepID }) else { return }
        await scheduleStartNotification(for: nextEvent, emoji: emojiProvider(nextEvent))
    }

    func handleTick(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        guard isEnabled else { return }
        let now = Date()
        var didFire = false
        for event in events where event.startDate <= now {
            let key = event.eventKey
            if ackStore.isPending(key) {
                continue
            } else if ackStore.record(for: key)?.status == .acknowledged {
                continue
            } else if ackStore.record(for: key) == nil, ackStore.canMarkPending(for: key) {
                let fired = coordinator.fireIfNeeded(key) {
                    self.ackStore.markPending(key)
                }
                didFire = didFire || fired
            }
        }
        if didFire {
            await scheduleUpcoming(events: events, emojiProvider: emojiProvider)
        }
        await processExpiredPending(events: events, emojiProvider: emojiProvider)
    }

    func acknowledge(_ key: EventKey) async {
        ackStore.markAcknowledged(key)
        coordinator.markFired(key)
        await removeNotifications(for: key)
        ackStore.pruneAcknowledgedAndExpired()
        ackStore.normalizePendingToSingle()
    }

    var pendingEvents: [AcknowledgmentRecord] {
        ackStore.primaryPendingRecord.map { [$0] } ?? []
    }

    private func wireDelegate() {
        delegate.onAcknowledge = { [weak self] storageKey in
            guard let self else { return }
            if let record = self.ackStore.records.first(where: { $0.key.storageKey == storageKey }) {
                Task { await self.onAcknowledged?(record.key) }
            } else if let eventKey = self.eventKey(fromStorageKey: storageKey) {
                Task { await self.onAcknowledged?(eventKey) }
            }
        }
        delegate.onExpire = { [weak self] storageKey in
            guard let self else { return }
            if let record = self.ackStore.records.first(where: { $0.key.storageKey == storageKey }) {
                self.ackStore.markExpired(record.key)
                Task { await self.removeNotifications(for: record.key) }
            }
        }
        delegate.onDelivered = { [weak self] storageKey in
            guard let self else { return }
            if let record = self.ackStore.records.first(where: { $0.key.storageKey == storageKey }) {
                if record.status != .pending, self.ackStore.canMarkPending(for: record.key) {
                    self.ackStore.markPending(record.key)
                }
            }
        }
    }

    private func registerCategories() async {
        let acknowledge = UNNotificationAction(identifier: "ACKNOWLEDGE", title: "Acknowledge", options: [.foreground])
        let joinCall = UNNotificationAction(
            identifier: "JOIN_CALL",
            title: "Join",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "video.fill")
        )
        let withCall = UNNotificationCategory(
            identifier: "EVENT_STARTED_CALL",
            actions: [joinCall],
            intentIdentifiers: []
        )
        let withoutCall = UNNotificationCategory(identifier: "EVENT_STARTED", actions: [acknowledge], intentIdentifiers: [])
        center.setNotificationCategories([withCall, withoutCall])
    }

    private func nextSchedulableEvent(in events: [CalendarEvent]) -> CalendarEvent? {
        let now = Date()
        return events
            .filter { $0.startDate > now }
            .first { event in
                let key = event.eventKey
                guard !coordinator.hasFired(key) else { return false }
                if ackStore.record(for: key)?.status == .acknowledged { return false }
                return true
            }
    }

    private func scheduleStartNotification(for event: CalendarEvent, emoji: EventEmojiResolution) async {
        guard event.startDate > Date() else { return }

        let key = event.eventKey
        let content = buildContent(for: event, emoji: emoji)
        content.userInfo = payload(for: key, action: "start", callURL: event.callLink)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: event.startDate
            ),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: key.notificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func removeNotifications(for key: EventKey) async {
        var identifiers = Set(notificationIDs(for: key))

        let pending = await center.pendingNotificationRequests()
        identifiers.formUnion(
            pending.map(\.identifier).filter { storageKey(fromNotificationID: $0) == key.storageKey }
        )

        let delivered = await center.deliveredNotifications()
        identifiers.formUnion(
            delivered.map(\.request.identifier).filter { storageKey(fromNotificationID: $0) == key.storageKey }
        )

        let ids = Array(identifiers)
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func notificationIDs(for key: EventKey) -> [String] {
        var ids = [key.notificationID, key.expireNotificationID]
        let legacyReminderCount = Int(AppConstants.ackWindowSeconds / AppConstants.reminderIntervalSeconds)
        for index in 1...legacyReminderCount {
            ids.append(key.reminderNotificationID(index: index))
        }
        return ids
    }

    private func cleanupOrphans(events: [CalendarEvent]) async {
        var validKeys = Set(ackStore.pendingRecords.map(\.key.storageKey))
        if ackStore.primaryPendingRecord == nil, let nextEvent = nextSchedulableEvent(in: events) {
            validKeys.insert(nextEvent.eventKey.storageKey)
        }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let allIDs = pending.map(\.identifier) + delivered.map(\.request.identifier)
        let orphans = allIDs.filter { id in
            guard id.hasPrefix(AppConstants.notificationPrefix) else { return false }
            guard let storageKey = storageKey(fromNotificationID: id) else { return true }
            return !validKeys.contains(storageKey)
        }
        center.removePendingNotificationRequests(withIdentifiers: orphans)
        center.removeDeliveredNotifications(withIdentifiers: orphans)
    }

    private func processExpiredPending(
        events: [CalendarEvent],
        emojiProvider: (CalendarEvent) -> EventEmojiResolution
    ) async {
        let stalePending = ackStore.records.filter { $0.status == .pending && ackStore.isExpired($0) }
        guard !stalePending.isEmpty else { return }

        for record in stalePending {
            ackStore.markExpired(record.key)
            coordinator.markFired(record.key)
            await removeNotifications(for: record.key)
        }
        ackStore.pruneAcknowledgedAndExpired()
        ackStore.normalizePendingToSingle()
        await removeDeliveredAcknowledgmentNotifications()
        await scheduleUpcoming(events: events, emojiProvider: emojiProvider)
    }

    private func removeDeliveredAcknowledgmentNotifications() async {
        let validPendingKeys = Set(ackStore.pendingRecords.map(\.key.storageKey))
        let delivered = await center.deliveredNotifications()
        let staleIDs = delivered.compactMap { notification -> String? in
            let id = notification.request.identifier
            guard id.hasPrefix(AppConstants.notificationPrefix) else { return nil }
            guard let storageKey = storageKey(fromNotificationID: id) else { return id }
            return validPendingKeys.contains(storageKey) ? nil : id
        }
        guard !staleIDs.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: staleIDs)
    }

    private func buildContent(for event: CalendarEvent, emoji: EventEmojiResolution) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = EventTitleEmoji.labeledTitle(fullTitle: event.title, resolution: emoji)
        content.subtitle = event.calendarTitle
        var bodyParts: [String] = [formattedStart(event)]
        if let location = event.location, !location.isEmpty { bodyParts.append(location) }
        if let notes = event.notes?.split(separator: "\n").first, !notes.isEmpty { bodyParts.append(String(notes)) }
        if let callLink = event.callLink { bodyParts.append(callLink.absoluteString) }
        content.body = bodyParts.joined(separator: " · ")
        content.categoryIdentifier = event.callLink == nil ? "EVENT_STARTED" : "EVENT_STARTED_CALL"
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    private func payload(for key: EventKey, action: String, callURL: URL? = nil) -> [String: Any] {
        var info: [String: Any] = ["eventKey": key.storageKey, "action": action]
        if let callURL {
            info["callURL"] = callURL.absoluteString
        }
        return info
    }

    private func formattedStart(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = event.isAllDay ? .none : .short
        return formatter.string(from: event.startDate)
    }

    private func storageKey(fromNotificationID id: String) -> String? {
        let prefix = AppConstants.notificationPrefix
        guard id.hasPrefix(prefix) else { return nil }
        let remainder = String(id.dropFirst(prefix.count))
        if let range = remainder.range(of: ".reminder.") ?? remainder.range(of: ".expire") ?? remainder.range(of: ".supplement.") {
            let base = String(remainder[..<range.lowerBound])
            return base.replacingOccurrences(of: ".", with: "|")
        }
        return remainder.replacingOccurrences(of: ".", with: "|")
    }

    private func eventKey(fromStorageKey storageKey: String) -> EventKey? {
        guard let separator = storageKey.firstIndex(of: "|") else { return nil }
        let eventIdentifier = String(storageKey[..<separator])
        let startString = String(storageKey[storageKey.index(after: separator)...])
        guard let startInterval = TimeInterval(startString) else { return nil }
        return EventKey(
            eventIdentifier: eventIdentifier,
            startDate: Date(timeIntervalSince1970: startInterval),
            title: "",
            calendarID: ""
        )
    }
}
