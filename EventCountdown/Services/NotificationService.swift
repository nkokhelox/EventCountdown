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
                onDelivered?(key)
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
    private var supplementTimer: Timer?
    private var expiryTimer: Timer?

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
        startTimers()
    }

    func requestPermission() async {
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        permissionGranted = granted ?? false
        await registerCategories()
    }

    func restoreOnLaunch(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        ackStore.normalizePendingToSingle()
        await cleanupOrphans()
        for record in ackStore.records {
            switch record.status {
            case .acknowledged, .expired:
                await removeNotifications(for: record.key)
            case .pending:
                guard record.id == ackStore.primaryPendingRecord?.id else {
                    await removeNotifications(for: record.key)
                    continue
                }
                if ackStore.isExpired(record) {
                    ackStore.markExpired(record.key)
                    await removeNotifications(for: record.key)
                } else {
                    await restorePending(
                        record.key,
                        event: events.first { $0.eventKey.matches(snapshot: record.key) } ?? CalendarEvent(from: record.key),
                        emoji: emojiProvider(events.first { $0.eventKey.matches(snapshot: record.key) } ?? CalendarEvent(from: record.key))
                    )
                }
            }
        }
        ackStore.pruneAcknowledgedAndExpired()
        if isEnabled {
            await scheduleUpcoming(events: events, emojiProvider: emojiProvider)
        }
    }

    func scheduleUpcoming(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        guard isEnabled else { return }
        let upcoming = events
            .filter { $0.startDate > Date() }
            .prefix(AppConstants.maxReminderChains)

        let keepIDs = Set(upcoming.flatMap { chainIDs(for: $0.eventKey) })
        let pending = await center.pendingNotificationRequests()
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(AppConstants.notificationPrefix) && !keepIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for event in upcoming {
            await scheduleChain(for: event, emoji: emojiProvider(event))
        }
    }

    func handleTick(events: [CalendarEvent], emojiProvider: (CalendarEvent) -> EventEmojiResolution) async {
        guard isEnabled else { return }
        let now = Date()
        for event in events where event.startDate <= now {
            let key = event.eventKey
            let emoji = emojiProvider(event)
            if ackStore.isPending(key) {
                if let record = ackStore.record(for: key), ackStore.isExpired(record) {
                    ackStore.markExpired(key)
                    await removeNotifications(for: key)
                }
            } else if ackStore.record(for: key)?.status == .acknowledged {
                continue
            } else if ackStore.record(for: key) == nil, ackStore.canMarkPending(for: key) {
                let fired = coordinator.fireIfNeeded(key) {
                    self.ackStore.markPending(key)
                }
                if fired {
                    await deliverNotification(for: event, emoji: emoji, isReminder: false)
                    await scheduleChain(for: event, emoji: emoji)
                }
            }
        }
        await processExpiredPending()
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
                Task { await self.acknowledge(record.key) }
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
            actions: [joinCall, acknowledge],
            intentIdentifiers: []
        )
        let withoutCall = UNNotificationCategory(identifier: "EVENT_STARTED", actions: [acknowledge], intentIdentifiers: [])
        center.setNotificationCategories([withCall, withoutCall])
    }

    private func scheduleChain(for event: CalendarEvent, emoji: EventEmojiResolution) async {
        let key = event.eventKey
        let start = event.startDate
        let interval = AppConstants.reminderIntervalSeconds
        let window = AppConstants.ackWindowSeconds
        let reminderCount = Int(window / interval)

        var requests: [UNNotificationRequest] = []

        let initial = buildContent(for: event, emoji: emoji, isReminder: false)
        initial.userInfo = payload(for: key, action: "start", callURL: event.callLink)
        if start > Date() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start), repeats: false)
            requests.append(UNNotificationRequest(identifier: key.notificationID, content: initial, trigger: trigger))
        }

        for index in 1...reminderCount {
            let fireDate = start.addingTimeInterval(interval * Double(index))
            guard fireDate <= start.addingTimeInterval(window), fireDate > Date() else { continue }
            let content = buildContent(for: event, emoji: emoji, isReminder: true)
            content.userInfo = payload(for: key, action: "reminder", callURL: event.callLink)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate),
                repeats: false
            )
            requests.append(UNNotificationRequest(identifier: key.reminderNotificationID(index: index), content: content, trigger: trigger))
        }

        let expireDate = start.addingTimeInterval(window)
        if expireDate > Date() {
            let expireContent = UNMutableNotificationContent()
            expireContent.title = "Event alert expired"
            expireContent.body = event.title
            expireContent.userInfo = payload(for: key, action: "expire")
            expireContent.sound = nil
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expireDate),
                repeats: false
            )
            requests.append(UNNotificationRequest(identifier: key.expireNotificationID, content: expireContent, trigger: trigger))
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    private func deliverNotification(for event: CalendarEvent, emoji: EventEmojiResolution, isReminder: Bool) async {
        guard isEnabled else { return }
        let content = buildContent(for: event, emoji: emoji, isReminder: isReminder)
        content.userInfo = payload(for: event.eventKey, action: isReminder ? "reminder" : "start", callURL: event.callLink)
        let request = UNNotificationRequest(identifier: event.eventKey.notificationID, content: content, trigger: nil)
        try? await center.add(request)
    }

    private func restorePending(_ key: EventKey, event: CalendarEvent, emoji: EventEmojiResolution) async {
        await deliverNotification(for: event, emoji: emoji, isReminder: true)
        await scheduleChain(for: event, emoji: emoji)
    }

    private func removeNotifications(for key: EventKey) async {
        let ids = chainIDs(for: key)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func chainIDs(for key: EventKey) -> [String] {
        var ids = [key.notificationID, key.expireNotificationID]
        let reminderCount = Int(AppConstants.ackWindowSeconds / AppConstants.reminderIntervalSeconds)
        for index in 1...reminderCount {
            ids.append(key.reminderNotificationID(index: index))
        }
        return ids
    }

    private func cleanupOrphans() async {
        let validKeys = Set(
            ackStore.primaryPendingRecord.map { [$0.key.storageKey] } ?? []
        )
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

    private func processExpiredPending() async {
        guard let record = ackStore.primaryPendingRecord, ackStore.isExpired(record) else { return }
        ackStore.markExpired(record.key)
        await removeNotifications(for: record.key)
    }

    private func buildContent(for event: CalendarEvent, emoji: EventEmojiResolution, isReminder: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = EventTitleEmoji.labeledTitle(fullTitle: event.title, resolution: emoji)
        content.subtitle = event.calendarTitle
        var bodyParts: [String] = [formattedStart(event)]
        if let location = event.location, !location.isEmpty { bodyParts.append(location) }
        if let notes = event.notes?.split(separator: "\n").first, !notes.isEmpty { bodyParts.append(String(notes)) }
        content.body = bodyParts.joined(separator: " · ")
        content.categoryIdentifier = event.callLink == nil ? "EVENT_STARTED" : "EVENT_STARTED_CALL"
        content.sound = isReminder ? nil : .default
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
        if let range = remainder.range(of: ".reminder.") ?? remainder.range(of: ".expire") {
            let base = String(remainder[..<range.lowerBound])
            return base.replacingOccurrences(of: ".", with: "|")
        }
        return remainder.replacingOccurrences(of: ".", with: "|")
    }

    private func startTimers() {
        supplementTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.reminderIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.supplementRedelivery() }
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.processExpiredPending() }
        }
    }

    private func supplementRedelivery() async {
        guard let record = ackStore.primaryPendingRecord, !ackStore.isExpired(record) else { return }
        let key = record.key
        let content = UNMutableNotificationContent()
        content.title = record.key.title
        content.body = "Reminder: event started"
        content.categoryIdentifier = "EVENT_STARTED"
        content.userInfo = payload(for: key, action: "reminder")
        let request = UNNotificationRequest(identifier: key.notificationID + ".supplement.\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        try? await center.add(request)
    }
}
