// SHARED – dodaj do wszystkich targetów
import Foundation
import UserNotifications
import SwiftData

enum ReminderAction {
    static let category = "MED_REMINDER"
    static let taken = "TAKEN"
    static let snooze = "SNOOZE"
    static let skip = "SKIP"
}

/// Architektura: dane synchronizują się przez iCloud (SwiftData + CloudKit),
/// a KAŻDE urządzenie samo planuje lokalne powiadomienia na podstawie tych danych.
/// Dzięki temu przypomnienia działają na wszystkich urządzeniach konta, także offline.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Zegarek domyślnie NIE planuje własnych powiadomień – dostaje te z iPhone'a
    /// (lustrzane, gdy iPhone jest zablokowany). Ustaw na true, jeśli chcesz, by zegarek
    /// dzwonił niezależnie od iPhone'a (uwaga: mogą się wtedy dublować).
    static let watchSchedulesOwnReminders = false

    // MARK: Konfiguracja

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let taken = UNNotificationAction(identifier: ReminderAction.taken, title: "Wzięte ✓", options: [])
        let snooze = UNNotificationAction(identifier: ReminderAction.snooze, title: "Za 10 min", options: [])
        let skip = UNNotificationAction(identifier: ReminderAction.skip, title: "Pomiń", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: ReminderAction.category,
            actions: [taken, snooze, skip],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        // .criticalAlert zadziała dopiero po zgodzie Apple (entitlement) – patrz instrukcja.
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
    }

    // MARK: Planowanie

    func reschedule(_ meds: [Medication]) async {
        #if os(watchOS)
        guard Self.watchSchedulesOwnReminders else { return }
        #endif

        let center = UNUserNotificationCenter.current()

        // Usuń tylko własne cykliczne przypomnienia (nie drzemki ani alerty o zapasie)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix("med|") }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        // iOS pozwala na max 64 oczekujące powiadomienia – leki krytyczne mają pierwszeństwo.
        var remaining = 60
        let ordered = meds.filter(\.isActive).sorted { $0.isCritical && !$1.isCritical }

        for med in ordered {
            for minutes in med.times {
                for request in makeRequests(for: med, minutes: minutes) where remaining > 0 {
                    try? await center.add(request)
                    remaining -= 1
                }
            }
        }
    }

    private func makeRequests(for med: Medication, minutes: Int) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = med.isCritical ? "⚠️ \(med.name)" : "💊 \(med.name)"
        content.body = med.dosage.isEmpty ? "Czas na dawkę." : med.dosage
        content.categoryIdentifier = ReminderAction.category
        content.threadIdentifier = med.id.uuidString
        content.userInfo = ["medID": med.id.uuidString, "minutes": minutes]

        if med.isCritical {
            content.sound = .defaultCritical          // przebija wyciszenie i „Nie przeszkadzać"
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            content.interruptionLevel = .timeSensitive // przebija tryby Skupienia
        }

        var base = DateComponents()
        base.hour = minutes / 60
        base.minute = minutes % 60

        // Wszystkie 7 dni = jedno powiadomienie (oszczędza limit 64)
        if med.weekdays.count == 7 {
            let trigger = UNCalendarNotificationTrigger(dateMatching: base, repeats: true)
            return [UNNotificationRequest(identifier: "med|\(med.id.uuidString)|\(minutes)|0",
                                          content: content, trigger: trigger)]
        }

        return med.weekdays.sorted().map { weekday in
            var comps = base
            comps.weekday = weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            return UNNotificationRequest(identifier: "med|\(med.id.uuidString)|\(minutes)|\(weekday)",
                                         content: content, trigger: trigger)
        }
    }

    func notifyLowStock(_ med: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Kończy się: \(med.name)"
        content.body = "Zostało \(med.pillsLeft) szt. Czas uzupełnić zapas."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "low|\(med.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let info = content.userInfo

        // Drzemka – nowe powiadomienie za 10 minut
        if action == ReminderAction.snooze {
            if let copy = content.mutableCopy() as? UNMutableNotificationContent {
                let request = UNNotificationRequest(
                    identifier: "snooze|\(UUID().uuidString)",
                    content: copy,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
                )
                try? await center.add(request)
            }
            return
        }

        guard action == ReminderAction.taken || action == ReminderAction.skip,
              let idString = info["medID"] as? String,
              let medID = UUID(uuidString: idString) else { return }

        let minutes = info["minutes"] as? Int ?? 0
        let delivered = response.notification.date
        await handle(taken: action == ReminderAction.taken, medID: medID, minutes: minutes, delivered: delivered)
    }

    private func handle(taken: Bool, medID: UUID, minutes: Int, delivered: Date) {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medID })
        guard let med = try? context.fetch(descriptor).first else { return }

        let scheduled = DoseEngine.date(minutes: minutes, on: delivered)
        DoseEngine.record(med, at: scheduled, status: taken ? .taken : .skipped, context: context)
        try? context.save()
    }
}
