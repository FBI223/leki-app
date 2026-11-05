// SHARED – dodaj do wszystkich targetów
import Foundation
import SwiftData

// MARK: Typy

/// Jednoznaczny identyfikator dawki: lek + dzień + minuta od północy.
nonisolated struct DoseKey: Hashable, Sendable {
    let medicationID: UUID
    let dayKey: String
    let minute: Int

    var id: String { "\(medicationID.uuidString)|\(dayKey)|\(minute)" }

    init(medicationID: UUID, dayKey: String, minute: Int) {
        self.medicationID = medicationID
        self.dayKey = dayKey
        self.minute = minute
    }

    init?(id: String) {
        let parts = id.split(separator: "|").map(String.init)
        guard parts.count == 3, let med = UUID(uuidString: parts[0]), let minute = Int(parts[2]) else { return nil }
        self.init(medicationID: med, dayKey: parts[1], minute: minute)
    }
}

enum DoseState {
    case taken, skipped
    /// godzina minęła, a dawka nie jest oznaczona
    case missed
    /// godzina jeszcze nie nadeszła
    case pending
    /// dawka sprzed dodania leku do aplikacji – można ją oznaczyć, ale nieoznaczona się nie liczy
    case ignored
}

struct ScheduledDose: Identifiable {
    let medication: Medication
    let date: Date
    let dayKey: String
    let minute: Int
    let log: DoseLog?
    /// false = wpis z historii, którego nie ma w planie (np. po zmianie godzin) – pokazujemy go dalej.
    let isPlanned: Bool
    let countsWhenUnmarked: Bool

    var key: DoseKey { DoseKey(medicationID: medication.id, dayKey: dayKey, minute: minute) }
    var id: String { key.id }

    func state(now: Date = .now) -> DoseState {
        if let log { return log.status == .taken ? .taken : .skipped }
        if !countsWhenUnmarked { return .ignored }
        return date <= now ? .missed : .pending
    }
}

enum DayState {
    case none, upcoming, complete, partial, missed
}

struct DayStat: Identifiable {
    let date: Date
    var taken = 0
    var skipped = 0
    var missed = 0
    var pending = 0

    var id: Date { date }
    /// Dawki, które już się liczą: wzięte, pominięte i te, których godzina minęła.
    var total: Int { taken + skipped + missed }
    var planned: Int { total + pending }
    var rate: Double? { total == 0 ? nil : Double(taken) / Double(total) }

    var state: DayState {
        if planned == 0 { return .none }
        if taken == planned { return .complete }
        if total == 0 { return .upcoming }
        if taken == 0 && pending == 0 { return .missed }
        return .partial
    }
}

// MARK: Indeks dawek

/// Migawka leków z gotowym indeksem historii. Budowana raz na odświeżenie widoku,
/// dzięki czemu kalendarz, statystyki i seria dni nie przeszukują wpisów w kółko.
@MainActor
struct DoseBook {
    private struct Version {
        let from: Date
        let to: Date?
        let times: [Int]
        let weekdays: Set<Int>
        let isActive: Bool
    }

    private struct Entry {
        let med: Medication
        let versions: [Version]
        let logs: [String: [Int: DoseLog]]
    }

    private let entries: [Entry]
    private let calendar: Calendar
    /// Najwcześniejszy dzień z planem – dalej wstecz nie ma czego liczyć.
    let firstDay: Date?

    init(meds: [Medication], calendar: Calendar = .current) {
        self.calendar = calendar
        var first: Date?
        entries = meds.map { med in
            var logs: [String: [Int: DoseLog]] = [:]
            for log in med.logs ?? [] {
                logs[log.dayKey, default: [:]][log.minute] = log
            }
            var versions = (med.schedules ?? []).map {
                Version(from: $0.validFrom, to: $0.validTo,
                        times: Self.decode($0.timesRaw).sorted(),
                        weekdays: Set(Self.decode($0.weekdaysRaw)),
                        isActive: $0.isActive)
            }
            if versions.isEmpty {
                // Zanim powstanie historia planu (PlanHistory.sync) – plan bieżący od dnia dodania.
                versions = [Version(from: calendar.startOfDay(for: med.createdAt), to: med.archivedAt,
                                    times: med.times, weekdays: med.weekdays, isActive: med.isActive)]
            }
            versions.sort { $0.from < $1.from }
            if let start = versions.first?.from { first = min(first ?? start, start) }
            return Entry(med: med, versions: versions, logs: logs)
        }
        firstDay = first.map { calendar.startOfDay(for: $0) }
    }

    /// Dawki danego dnia wg planu, który obowiązywał w chwili każdej dawki,
    /// plus wpisy z historii spoza planu.
    func doses(on day: Date) -> [ScheduledDose] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let dayKey = DayKey.string(for: start, calendar: calendar)
        let weekday = calendar.component(.weekday, from: start)

        var result: [ScheduledDose] = []
        for entry in entries {
            let dayLogs = entry.logs[dayKey] ?? [:]
            var planned = Set<Int>()

            for version in entry.versions where version.from < end && (version.to.map { $0 > start } ?? true) {
                guard version.isActive, version.weekdays.contains(weekday) else { continue }
                for minute in version.times where !planned.contains(minute) {
                    let date = DoseEngine.date(minutes: minute, on: start, calendar: calendar)
                    guard date >= version.from, version.to.map({ date < $0 }) ?? true else { continue }
                    planned.insert(minute)
                    result.append(ScheduledDose(
                        medication: entry.med, date: date, dayKey: dayKey, minute: minute,
                        log: dayLogs[minute], isPlanned: true,
                        countsWhenUnmarked: date >= entry.med.createdAt
                    ))
                }
            }
            for (minute, log) in dayLogs where !planned.contains(minute) {
                result.append(ScheduledDose(
                    medication: entry.med, date: DoseEngine.date(minutes: minute, on: start, calendar: calendar),
                    dayKey: dayKey, minute: minute, log: log, isPlanned: false, countsWhenUnmarked: true
                ))
            }
        }
        return result.sorted { ($0.date, $0.medication.name) < ($1.date, $1.medication.name) }
    }

    func stat(on day: Date, now: Date = .now) -> DayStat {
        var stat = DayStat(date: calendar.startOfDay(for: day))
        for dose in doses(on: day) {
            switch dose.state(now: now) {
            case .taken: stat.taken += 1
            case .skipped: stat.skipped += 1
            case .missed: stat.missed += 1
            case .pending: stat.pending += 1
            case .ignored: break
            }
        }
        return stat
    }

    /// Liczba kolejnych dni (wstecz od dziś), w których wzięto wszystkie należne dawki.
    /// Dni bez dawek nie przerywają serii; dzisiaj jej nie przerywa, bo jeszcze trwa.
    /// Pominięcie dawki („Pomiń”) przerywa serię – to nie jest wzięcie leku.
    func streak(now: Date = .now) -> Int {
        guard let firstDay else { return 0 }
        let today = calendar.startOfDay(for: now)
        var count = 0
        var day = today
        var offset = 0
        while day >= firstDay && offset < 366 {
            let s = stat(on: day, now: now)
            if s.total > 0 {
                if s.taken == s.total {
                    count += 1
                } else if offset > 0 {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            offset += 1
        }
        return count
    }

    private static func decode(_ raw: String) -> [Int] {
        raw.split(separator: ",").compactMap { Int($0) }
    }
}

// MARK: Silnik

@MainActor
enum DoseEngine {

    // MARK: Czas

    nonisolated static func date(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return calendar.date(from: comps) ?? day
    }

    nonisolated static func date(minutes: Int, dayKey: String, calendar: Calendar = .current) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                  hour: minutes / 60, minute: minutes % 60))
    }

    nonisolated static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    nonisolated static func timeLabel(_ minutes: Int) -> String {
        date(minutes: minutes, on: .now).formatted(date: .omitted, time: .shortened)
    }

    static func adherence(_ stats: [DayStat]) -> Double? {
        let total = stats.reduce(0) { $0 + $1.total }
        guard total > 0 else { return nil }
        return Double(stats.reduce(0) { $0 + $1.taken }) / Double(total)
    }

    // MARK: Zapis dawek

    static func log(for med: Medication, dayKey: String, minute: Int) -> DoseLog? {
        med.logs?.first { $0.dayKey == dayKey && $0.minute == minute }
    }

    static func record(_ dose: ScheduledDose, status: DoseStatus, context: ModelContext) {
        record(dose.medication, dayKey: dose.dayKey, minute: dose.minute,
               scheduledAt: dose.date, status: status, context: context)
    }

    static func record(_ med: Medication, dayKey: String, minute: Int, scheduledAt: Date,
                       status: DoseStatus, context: ModelContext) {
        var available = med.pillsLeft
        if let existing = log(for: med, dayKey: dayKey, minute: minute) {
            available += existing.pillsDeducted
            remove(existing, context: context)
        }
        // Nigdy nie odejmujemy więcej, niż jest – cofnięcie odda dokładnie tyle samo.
        let deducted = (status == .taken && med.tracksStock) ? min(med.pillsPerDose, max(0, available)) : 0
        let before = med.pillsLeft

        let entry = DoseLog(scheduledAt: scheduledAt, dayKey: dayKey, minute: minute, status: status)
        entry.pillsDeducted = deducted
        entry.medName = med.name
        entry.dosage = med.dosage
        context.insert(entry)
        entry.medication = med
        med.pillsLeft = available - deducted

        if med.tracksStock, before > med.refillThreshold, med.pillsLeft <= med.refillThreshold {
            NotificationService.shared.notifyLowStock(med)
        }
        try? context.save()
        NotificationService.shared.doseResolved(DoseKey(medicationID: med.id, dayKey: dayKey, minute: minute))
    }

    static func undo(_ entry: DoseLog, context: ModelContext) {
        let key = entry.medication.map { DoseKey(medicationID: $0.id, dayKey: entry.dayKey, minute: entry.minute) }
        if let med = entry.medication, entry.pillsDeducted > 0 {
            med.pillsLeft += entry.pillsDeducted
        }
        remove(entry, context: context)
        try? context.save()
        if let key { NotificationService.shared.doseResolved(key) }
    }

    private static func remove(_ entry: DoseLog, context: ModelContext) {
        entry.medication?.logs?.removeAll { $0.id == entry.id }
        context.delete(entry)
    }
}

// MARK: Historia planu

/// Pilnuje, żeby zmiana planu leku działała tylko „od teraz”, a przeszłe dni
/// liczyły się wg planu, który wtedy obowiązywał.
@MainActor
enum PlanHistory {

    /// Uzgadnia wersje planu wszystkich leków (uruchamiane przy starcie i po synchronizacji iCloud).
    static func syncAll(context: ModelContext, now: Date = .now) {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        for med in meds { sync(med, context: context, now: now) }
        if context.hasChanges { try? context.save() }
    }

    static func sync(_ med: Medication, context: ModelContext, now: Date = .now) {
        let all = med.schedules ?? []
        var open = all.filter { $0.validTo == nil }.sorted { $0.validFrom < $1.validFrom }

        // Kilka otwartych wersji (np. utworzonych na dwóch urządzeniach) – zostaw najnowszą.
        if open.count > 1, let keep = open.popLast() {
            for extra in open { close(extra, at: keep.validFrom, med: med, context: context) }
            open = [keep]
        }
        let current = open.first

        if let archivedAt = med.archivedAt {
            if let current { close(current, at: archivedAt, med: med, context: context) }
            return
        }

        if let current,
           current.timesRaw == med.timesRaw,
           current.weekdaysRaw == med.weekdaysRaw,
           current.isActive == med.isActive {
            return
        }

        if let current {
            let calendar = Calendar.current
            let startedToday = calendar.isDate(current.validFrom, inSameDayAs: now)
            let usedSinceStart = med.logs?.contains { $0.scheduledAt >= current.validFrom } ?? false
            if startedToday && !usedSinceStart {
                // Plan z dzisiaj, bez żadnej oznaczonej dawki – poprawiamy go w miejscu.
                current.timesRaw = med.timesRaw
                current.weekdaysRaw = med.weekdaysRaw
                current.isActive = med.isActive
                return
            }
            close(current, at: now, med: med, context: context)
        }

        let start = all.isEmpty ? Calendar.current.startOfDay(for: med.createdAt) : now
        let version = MedSchedule(validFrom: start, timesRaw: med.timesRaw,
                                  weekdaysRaw: med.weekdaysRaw, isActive: med.isActive)
        context.insert(version)
        version.medication = med
    }

    private static func close(_ version: MedSchedule, at date: Date, med: Medication, context: ModelContext) {
        if date <= version.validFrom {
            med.schedules?.removeAll { $0.id == version.id }
            context.delete(version)
        } else {
            version.validTo = date
        }
    }
}
