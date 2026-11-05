// SHARED – dodaj do wszystkich targetów
import Foundation
import UserNotifications
import SwiftData

nonisolated enum ReminderAction {
    static let category = "MED_REMINDER"
    static let taken = "TAKEN"
    static let snooze = "SNOOZE"
    static let skip = "SKIP"
}

nonisolated enum ReminderID {
    static let dosePrefix = "dose|"
    static let userInfoKey = "doseKey"

    static func dose(_ key: DoseKey) -> String { "dose|\(key.id)" }
    static func followUp(_ key: DoseKey, after minutes: Int) -> String { "dose|\(key.id)|+\(minutes)" }
    static func snooze(_ key: DoseKey) -> String { "snooze|\(key.id)" }
    static func lowStock(_ medicationID: UUID) -> String { "low|\(medicationID.uuidString)" }

    /// Wszystkie powiadomienia należące do jednej dawki.
    static func all(for key: DoseKey) -> [String] {
        [dose(key), snooze(key)] + AppFeatures.criticalFollowUpMinutes.map { followUp(key, after: $0) }
    }
}

/// Architektura: dane są w bazie SwiftData (opcjonalnie synchronizowanej przez iCloud),
/// a KAŻDE urządzenie samo planuje lokalne powiadomienia na podstawie tych danych.
///
/// Przypomnienia są JEDNORAZOWE – osobne dla każdej dawki (lek + dzień + godzina) na najbliższe
/// `AppFeatures.schedulingWindowDays` dni. Dzięki temu dawka oznaczona wcześniej (np. o 7:50
/// zamiast 8:00) usuwa swoje przypomnienie i nie dostajesz go już po wzięciu leku.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var refreshTask: Task<Void, Never>?
    private var center: UNUserNotificationCenter { .current() }

    // MARK: Konfiguracja

    func configure() {
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
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if AppFeatures.criticalAlertsEnabled { options.insert(.criticalAlert) }
        _ = try? await center.requestAuthorization(options: options)
    }

    // MARK: Planowanie

    /// Odświeża plan powiadomień chwilę po ostatniej zmianie (seria szybkich zmian = jedno odświeżenie).
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    func reschedule() async {
        #if os(watchOS)
        guard AppFeatures.watchSchedulesOwnReminders else { return }
        #endif

        let context = PersistenceController.shared.container.mainContext
        let meds = ((try? context.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isScheduledNow)
        let book = DoseBook(meds: meds)
        let now = Date.now
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var planned: [(fire: Date, request: UNNotificationRequest)] = []
        for offset in 0..<AppFeatures.schedulingWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for dose in book.doses(on: day) where dose.log == nil && dose.isPlanned {
                if dose.date > now {
                    planned.append((dose.date, makeRequest(for: dose, followUpAfter: nil)))
                }
                if dose.medication.isCritical {
                    for minutes in AppFeatures.criticalFollowUpMinutes {
                        let fire = dose.date.addingTimeInterval(TimeInterval(minutes * 60))
                        if fire > now {
                            planned.append((fire, makeRequest(for: dose, followUpAfter: minutes)))
                        }
                    }
                }
            }
        }
        planned.sort { $0.fire < $1.fire }

        // Usuń tylko przypomnienia o dawkach (nie drzemki ani alerty o zapasie) i zaplanuj od nowa.
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(ReminderID.dosePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for item in planned.prefix(AppFeatures.maxScheduledNotifications) {
            try? await center.add(item.request)
        }
    }

    private func makeRequest(for dose: ScheduledDose, followUpAfter minutes: Int?) -> UNNotificationRequest {
        let med = dose.medication
        let content = UNMutableNotificationContent()
        content.title = med.isCritical ? "⚠️ \(med.name)" : "💊 \(med.name)"
        if minutes != nil {
            content.body = "Dawka z \(DoseEngine.timeLabel(dose.minute)) nie jest jeszcze oznaczona."
        } else {
            content.body = med.dosage.isEmpty ? "Czas na dawkę." : med.dosage
        }
        content.categoryIdentifier = ReminderAction.category
        content.threadIdentifier = med.id.uuidString
        content.userInfo = [ReminderID.userInfoKey: dose.key.id]

        if med.isCritical && AppFeatures.criticalAlertsEnabled {
            content.sound = .defaultCritical          // przebija wyciszenie i „Nie przeszkadzać"
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            // Bez uprawnienia „time sensitive” (płatne konto) system traktuje to jak zwykłe powiadomienie.
            content.interruptionLevel = .timeSensitive
        }

        let fire = dose.date.addingTimeInterval(TimeInterval((minutes ?? 0) * 60))
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let id = minutes.map { ReminderID.followUp(dose.key, after: $0) } ?? ReminderID.dose(dose.key)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// Dawka została oznaczona lub cofnięta: usuń jej przypomnienia, ponowienia, drzemkę
    /// i baner z centrum powiadomień, a potem przelicz plan (cofnięcie przywróci przypomnienie).
    func doseResolved(_ key: DoseKey) {
        let ids = ReminderID.all(for: key)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        scheduleRefresh()
    }

    func notifyLowStock(_ med: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Kończy się: \(med.name)"
        content.body = "Zostało \(med.pillsLeft) szt. Czas uzupełnić zapas."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: ReminderID.lowStock(med.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        center.add(request)
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
        guard let raw = content.userInfo[ReminderID.userInfoKey] as? String,
              let key = DoseKey(id: raw) else { return }

        switch action {
        case ReminderAction.snooze:
            guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
            let request = UNNotificationRequest(
                identifier: ReminderID.snooze(key),
                content: copy,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
            )
            try? await center.add(request)
        case ReminderAction.taken:
            await handle(key, status: .taken)
        case ReminderAction.skip:
            await handle(key, status: .skipped)
        default:
            break
        }
    }

    private func handle(_ key: DoseKey, status: DoseStatus) {
        let context = PersistenceController.shared.container.mainContext
        let medID = key.medicationID
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medID })
        guard let med = try? context.fetch(descriptor).first,
              let scheduled = DoseEngine.date(minutes: key.minute, dayKey: key.dayKey) else { return }
        DoseEngine.record(med, dayKey: key.dayKey, minute: key.minute, scheduledAt: scheduled,
                          status: status, context: context)
    }
}
