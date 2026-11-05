// SHARED – dodaj do wszystkich targetów
// Synchronizacja iPhone ↔ Apple Watch przez WatchConnectivity (bez iCloud, działa na darmowym koncie).
//
// • iPhone = źródło prawdy. Po każdym zapisie bazy wysyła na zegarek migawkę: leki, wersje planu
//   i historię z ostatnich dni (updateApplicationContext – dociera, gdy tylko zegarek będzie dostępny).
// • Zegarek trzyma lustrzaną kopię. Oznaczenie dawki na zegarku działa od razu lokalnie i jest
//   wysyłane do iPhone'a (transferUserInfo – kolejka, dostarczana także później).
// • Akcje są idempotentne, więc ponowne wysłanie tej samej akcji niczego nie psuje.
import Foundation
import SwiftData
#if os(iOS) || os(watchOS)
import WatchConnectivity
#endif

// MARK: Dane przesyłane między urządzeniami

nonisolated struct SyncSnapshot: Codable, Sendable {
    var generatedAt: Date
    var medications: [MedicationDTO]
}

nonisolated struct MedicationDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var dosage: String
    var notes: String
    var colorName: String
    var symbol: String
    var timesRaw: String
    var weekdaysRaw: String
    var isCritical: Bool
    var isActive: Bool
    var tracksStock: Bool
    var pillsLeft: Int
    var pillsPerDose: Int
    var refillThreshold: Int
    var createdAt: Date
    var archivedAt: Date?
    var schedules: [ScheduleDTO]
    var logs: [DoseLogDTO]
}

nonisolated struct ScheduleDTO: Codable, Sendable {
    var id: UUID
    var validFrom: Date
    var validTo: Date?
    var timesRaw: String
    var weekdaysRaw: String
    var isActive: Bool
}

nonisolated struct DoseLogDTO: Codable, Sendable {
    var id: UUID
    var scheduledAt: Date
    var dayKey: String
    var minute: Int
    var resolvedAt: Date
    var statusRaw: String
    var pillsDeducted: Int
    var medName: String
    var dosage: String
}

/// Akcja z zegarka: oznaczenie dawki (status) albo cofnięcie (status == nil).
nonisolated struct DoseAction: Codable, Sendable {
    var id: UUID
    var doseKey: String
    var statusRaw: String?
    var createdAt: Date
}

// MARK: Synchronizacja

@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    /// Klucz w UserDefaults z czasem ostatniej synchronizacji (sekundy od 1970) – widok zegarka go obserwuje.
    static let lastSyncKey = "watchSync.lastSync"
    private static let pendingKey = "watchSync.pendingActions"
    /// Ile dni historii trafia na zegarek (limit rozmiaru danych WatchConnectivity).
    private static let historyDays = 7

    private var pushTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?

    var isEnabled: Bool {
        #if os(iOS) || os(watchOS)
        return AppFeatures.watchSyncEnabled && WCSession.isSupported()
        #else
        return false
        #endif
    }

    func activate() {
        #if os(iOS) || os(watchOS)
        guard isEnabled else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif

        #if os(iOS)
        // Każdy zapis bazy na iPhonie (dawka, edycja leku, archiwum…) = nowa migawka dla zegarka.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WatchSync.shared.scheduleSnapshot() }
        }
        #endif
    }

    // MARK: iPhone → zegarek

    /// Wysyła migawkę chwilę po ostatniej zmianie (seria zmian = jedna wysyłka).
    func scheduleSnapshot() {
        #if os(iOS)
        guard isEnabled else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            pushSnapshot()
        }
        #endif
    }

    #if os(iOS)
    private func pushSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(makeSnapshot()) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    private func makeSnapshot() -> SyncSnapshot {
        let context = PersistenceController.shared.container.mainContext
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let today = Calendar.current.startOfDay(for: .now)
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: today) ?? today

        return SyncSnapshot(generatedAt: .now, medications: meds.map { med in
            MedicationDTO(
                id: med.id, name: med.name, dosage: med.dosage, notes: med.notes,
                colorName: med.colorName, symbol: med.symbol,
                timesRaw: med.timesRaw, weekdaysRaw: med.weekdaysRaw,
                isCritical: med.isCritical, isActive: med.isActive,
                tracksStock: med.tracksStock, pillsLeft: med.pillsLeft,
                pillsPerDose: med.pillsPerDose, refillThreshold: med.refillThreshold,
                createdAt: med.createdAt, archivedAt: med.archivedAt,
                schedules: (med.schedules ?? []).map {
                    ScheduleDTO(id: $0.id, validFrom: $0.validFrom, validTo: $0.validTo,
                                timesRaw: $0.timesRaw, weekdaysRaw: $0.weekdaysRaw, isActive: $0.isActive)
                },
                logs: (med.logs ?? []).filter { $0.scheduledAt >= cutoff }.map {
                    DoseLogDTO(id: $0.id, scheduledAt: $0.scheduledAt, dayKey: $0.dayKey, minute: $0.minute,
                               resolvedAt: $0.resolvedAt, statusRaw: $0.statusRaw,
                               pillsDeducted: $0.pillsDeducted, medName: $0.medName, dosage: $0.dosage)
                }
            )
        })
    }

    /// Akcja z zegarka – zapisz ją w bazie iPhone'a (to wywoła też nową migawkę).
    private func receiveAction(_ data: Data) {
        guard let action = try? JSONDecoder().decode(DoseAction.self, from: data),
              let key = DoseKey(id: action.doseKey) else { return }
        let context = PersistenceController.shared.container.mainContext
        let medID = key.medicationID
        guard let med = try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medID })).first
        else { return }

        if let raw = action.statusRaw, let status = DoseStatus(rawValue: raw) {
            guard let scheduled = DoseEngine.date(minutes: key.minute, dayKey: key.dayKey) else { return }
            if DoseEngine.log(for: med, dayKey: key.dayKey, minute: key.minute)?.status == status {
                scheduleSnapshot()   // już zapisane – tylko potwierdź zegarkowi
                return
            }
            DoseEngine.record(med, dayKey: key.dayKey, minute: key.minute, scheduledAt: scheduled,
                              status: status, context: context)
        } else if let log = DoseEngine.log(for: med, dayKey: key.dayKey, minute: key.minute) {
            DoseEngine.undo(log, context: context)
        } else {
            scheduleSnapshot()
        }
    }
    #endif

    // MARK: Zegarek → iPhone

    /// Wysyła na iPhone'a oznaczenie dawki lub jego cofnięcie (status == nil).
    func send(_ key: DoseKey, status: DoseStatus?) {
        #if os(watchOS)
        guard isEnabled else { return }
        let action = DoseAction(id: UUID(), doseKey: key.id, statusRaw: status?.rawValue, createdAt: .now)
        var pending = loadPending()
        pending.append(action)
        savePending(pending)
        transfer(action)
        #endif
    }

    /// Prośba do iPhone'a o świeże dane (gdy jest w zasięgu).
    func requestSnapshot() {
        #if os(watchOS)
        guard isEnabled else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: nil, errorHandler: nil)
        #endif
    }

    #if os(watchOS)
    private func transfer(_ action: DoseAction) {
        let session = WCSession.default
        guard session.activationState == .activated, let data = try? JSONEncoder().encode(action) else { return }
        session.transferUserInfo(["action": data])
    }

    private func receiveSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: data) else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        guard snapshot.generatedAt.timeIntervalSince1970 > last else { return }   // starsza migawka

        apply(snapshot)
        UserDefaults.standard.set(snapshot.generatedAt.timeIntervalSince1970, forKey: Self.lastSyncKey)
    }

    /// Zastępuje lokalną kopię danymi z iPhone'a, a potem nakłada akcje, których iPhone jeszcze nie widział.
    private func apply(_ snapshot: SyncSnapshot) {
        let context = PersistenceController.shared.container.mainContext
        let local = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let incoming = Set(snapshot.medications.map(\.id))
        var byID: [UUID: Medication] = [:]
        for med in local {
            if incoming.contains(med.id), byID[med.id] == nil { byID[med.id] = med } else { context.delete(med) }
        }

        for dto in snapshot.medications {
            let med: Medication
            if let existing = byID[dto.id] {
                med = existing
            } else {
                med = Medication()
                med.id = dto.id
                context.insert(med)
            }
            med.name = dto.name
            med.dosage = dto.dosage
            med.notes = dto.notes
            med.colorName = dto.colorName
            med.symbol = dto.symbol
            med.timesRaw = dto.timesRaw
            med.weekdaysRaw = dto.weekdaysRaw
            med.isCritical = dto.isCritical
            med.isActive = dto.isActive
            med.tracksStock = dto.tracksStock
            med.pillsLeft = dto.pillsLeft
            med.pillsPerDose = dto.pillsPerDose
            med.refillThreshold = dto.refillThreshold
            med.createdAt = dto.createdAt
            med.archivedAt = dto.archivedAt

            for schedule in med.schedules ?? [] { context.delete(schedule) }
            med.schedules = []
            for s in dto.schedules {
                let version = MedSchedule(validFrom: s.validFrom, timesRaw: s.timesRaw,
                                          weekdaysRaw: s.weekdaysRaw, isActive: s.isActive)
                version.id = s.id
                version.validTo = s.validTo
                context.insert(version)
                version.medication = med
            }

            for log in med.logs ?? [] { context.delete(log) }
            med.logs = []
            for l in dto.logs {
                let log = DoseLog(scheduledAt: l.scheduledAt, dayKey: l.dayKey, minute: l.minute,
                                  status: DoseStatus(rawValue: l.statusRaw) ?? .taken)
                log.id = l.id
                log.resolvedAt = l.resolvedAt
                log.pillsDeducted = l.pillsDeducted
                log.medName = l.medName
                log.dosage = l.dosage
                context.insert(log)
                log.medication = med
            }
            byID[dto.id] = med
        }

        // Akcje starsze niż migawka iPhone już uwzględnił; nowsze nakładamy ponownie.
        let pending = loadPending().filter { $0.createdAt > snapshot.generatedAt }
        savePending(pending)
        for action in pending {
            guard let key = DoseKey(id: action.doseKey), let med = byID[key.medicationID] else { continue }
            if let old = DoseEngine.log(for: med, dayKey: key.dayKey, minute: key.minute) {
                med.logs?.removeAll { $0.id == old.id }
                context.delete(old)
            }
            if let raw = action.statusRaw, let status = DoseStatus(rawValue: raw),
               let scheduled = DoseEngine.date(minutes: key.minute, dayKey: key.dayKey) {
                let log = DoseLog(scheduledAt: scheduled, dayKey: key.dayKey, minute: key.minute, status: status)
                log.medName = med.name
                log.dosage = med.dosage
                context.insert(log)
                log.medication = med
            }
        }
        try? context.save()
    }

    private func didActivateOnWatch() {
        if let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data {
            receiveSnapshot(data)
        }
        // Wyślij ponownie akcje bez potwierdzenia (np. zapisane, zanim sesja była gotowa).
        for action in loadPending() { transfer(action) }
        requestSnapshot()
    }

    private func loadPending() -> [DoseAction] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKey) else { return [] }
        let cutoff = Date.now.addingTimeInterval(-2 * 24 * 3600)
        return ((try? JSONDecoder().decode([DoseAction].self, from: data)) ?? []).filter { $0.createdAt > cutoff }
    }

    private func savePending(_ actions: [DoseAction]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(actions), forKey: Self.pendingKey)
    }
    #endif
}

// MARK: WCSessionDelegate

#if os(iOS) || os(watchOS)
extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            #if os(iOS)
            self.scheduleSnapshot()
            #else
            self.didActivateOnWatch()
            #endif
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // np. po przełączeniu na inny zegarek
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.scheduleSnapshot() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo["action"] as? Data else { return }
        Task { @MainActor in self.receiveAction(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["request"] as? String == "snapshot" else { return }
        Task { @MainActor in self.pushSnapshot() }
    }
    #endif

    #if os(watchOS)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in self.receiveSnapshot(data) }
    }
    #endif
}
#endif
