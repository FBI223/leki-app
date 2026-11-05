// SHARED – dodaj do wszystkich targetów
import Foundation
import SwiftData

struct ScheduledDose: Identifiable {
    let medication: Medication
    let date: Date
    var id: String { "\(medication.id.uuidString)-\(Int(date.timeIntervalSince1970))" }
}

struct DayStat: Identifiable {
    let date: Date
    let taken: Int
    let total: Int
    var id: Date { date }
}

@MainActor
enum DoseEngine {

    // MARK: Czas

    nonisolated static func date(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    nonisolated static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    nonisolated static func timeLabel(_ minutes: Int) -> String {
        date(minutes: minutes, on: .now).formatted(date: .omitted, time: .shortened)
    }

    // MARK: Plan dnia

    static func doses(on day: Date, for meds: [Medication]) -> [ScheduledDose] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let weekday = cal.component(.weekday, from: start)

        return meds
            .filter { $0.isActive
                && $0.weekdays.contains(weekday)
                && cal.startOfDay(for: $0.createdAt) <= start }
            .flatMap { med in
                med.times.map { ScheduledDose(medication: med, date: date(minutes: $0, on: start)) }
            }
            .sorted { $0.date < $1.date }
    }

    static func log(for dose: ScheduledDose) -> DoseLog? {
        log(for: dose.medication, at: dose.date)
    }

    static func log(for med: Medication, at date: Date) -> DoseLog? {
        med.logs?.first { Calendar.current.isDate($0.scheduledAt, equalTo: date, toGranularity: .minute) }
    }

    // MARK: Zapis dawek

    static func record(_ med: Medication, at date: Date, status: DoseStatus, context: ModelContext) {
        if let existing = log(for: med, at: date) {
            undo(existing, context: context)
        }
        let entry = DoseLog(scheduledAt: date, status: status)
        context.insert(entry)
        entry.medication = med

        if status == .taken, med.tracksStock {
            let before = med.pillsLeft
            med.pillsLeft = max(0, before - med.pillsPerDose)
            if before > med.refillThreshold, med.pillsLeft <= med.refillThreshold {
                NotificationService.shared.notifyLowStock(med)
            }
        }
    }

    static func undo(_ entry: DoseLog, context: ModelContext) {
        if let med = entry.medication {
            if entry.status == .taken, med.tracksStock {
                med.pillsLeft += med.pillsPerDose
            }
            med.logs?.removeAll { $0.id == entry.id }
        }
        context.delete(entry)
    }

    // MARK: Statystyki

    static func stat(on day: Date, meds: [Medication], now: Date = .now) -> DayStat {
        var taken = 0
        var total = 0
        for dose in doses(on: day, for: meds) {
            let entry = log(for: dose)
            if entry?.status == .taken {
                taken += 1
                total += 1
            } else if dose.date <= now || entry != nil {
                total += 1   // minęła godzina albo pominięta – liczy się jako niewzięta
            }
        }
        return DayStat(date: Calendar.current.startOfDay(for: day), taken: taken, total: total)
    }

    static func history(days: Int, meds: [Medication]) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<days).reversed()
            .compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .map { stat(on: $0, meds: meds) }
    }

    /// Liczba kolejnych dni, w których wzięto wszystkie dawki.
    static func streak(meds: [Medication]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var count = 0
        for offset in 0..<365 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { break }
            let s = stat(on: day, meds: meds)
            if s.total == 0 { continue }
            if s.taken == s.total {
                count += 1
            } else if offset == 0 {
                continue          // dzisiaj jeszcze trwa
            } else {
                break
            }
        }
        return count
    }
}
