// SHARED – dodaj do wszystkich targetów (iOS/iPadOS/macOS + watchOS)
import SwiftData
import SwiftUI

enum DoseStatus: String {
    case taken, skipped
}

struct PaletteColor: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

enum MedPalette {
    static let colors: [PaletteColor] = [
        .init(name: "blue", color: .blue), .init(name: "teal", color: .teal),
        .init(name: "green", color: .green), .init(name: "orange", color: .orange),
        .init(name: "pink", color: .pink), .init(name: "purple", color: .purple),
        .init(name: "red", color: .red), .init(name: "indigo", color: .indigo)
    ]

    static let symbols = [
        "pills.fill", "pill.fill", "cross.vial.fill", "syringe.fill", "drop.fill", "eyedropper",
        "heart.fill", "lungs.fill", "brain.head.profile", "bandage.fill", "leaf.fill", "moon.zzz.fill"
    ]

    static func color(named name: String) -> Color {
        colors.first { $0.name == name }?.color ?? .blue
    }
}

/// Dzień kalendarzowy jako tekst "yyyy-MM-dd" – jednoznaczny klucz dawki w historii
/// (bez porównywania dat z dokładnością do minuty i bez problemów ze zmianą czasu).
enum DayKey {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// Uwaga: modele zgodne z CloudKit – każda właściwość ma wartość domyślną,
// relacje są opcjonalne i mają odwrotność, brak @Attribute(.unique).

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dosage: String = ""
    var notes: String = ""
    var colorName: String = "blue"
    var symbol: String = "pills.fill"

    /// BIEŻĄCY plan: godziny jako minuty od północy, np. "480,1200" = 8:00 i 20:00.
    /// Historia planu jest w `schedules` – przeszłe dni liczą się wg planu, który wtedy obowiązywał.
    var timesRaw: String = "480"
    /// Dni tygodnia wg Calendar (1 = niedziela … 7 = sobota)
    var weekdaysRaw: String = "1,2,3,4,5,6,7"

    var isCritical: Bool = false
    var isActive: Bool = true

    var tracksStock: Bool = false
    var pillsLeft: Int = 30
    var pillsPerDose: Int = 1
    var refillThreshold: Int = 7

    var createdAt: Date = Date()
    /// Lek w archiwum: bez planu i przypomnień, ale z zachowaną historią.
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
    var logs: [DoseLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \MedSchedule.medication)
    var schedules: [MedSchedule]? = []

    init(name: String = "", dosage: String = "", times: [Int] = [480]) {
        self.name = name
        self.dosage = dosage
        self.times = times
    }

    var times: [Int] {
        get { timesRaw.split(separator: ",").compactMap { Int($0) }.sorted() }
        set { timesRaw = Array(Set(newValue)).sorted().map(String.init).joined(separator: ",") }
    }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var color: Color { MedPalette.color(named: colorName) }
    var isArchived: Bool { archivedAt != nil }
    var isLowOnStock: Bool { tracksStock && pillsLeft <= refillThreshold }
    /// Czy lek ma teraz wysyłać przypomnienia.
    var isScheduledNow: Bool { isActive && !isArchived }
}

/// Jedna wersja planu leku, obowiązująca w przedziale [validFrom, validTo).
/// Zmiana godzin/dni/wstrzymanie zamyka bieżącą wersję i otwiera nową od tej chwili.
@Model
final class MedSchedule {
    var id: UUID = UUID()
    var validFrom: Date = Date()
    /// nil = obowiązuje nadal
    var validTo: Date?
    var timesRaw: String = ""
    var weekdaysRaw: String = ""
    var isActive: Bool = true
    var medication: Medication?

    init(validFrom: Date, timesRaw: String, weekdaysRaw: String, isActive: Bool) {
        self.validFrom = validFrom
        self.timesRaw = timesRaw
        self.weekdaysRaw = weekdaysRaw
        self.isActive = isActive
    }
}

@Model
final class DoseLog {
    var id: UUID = UUID()
    /// Planowana godzina dawki (sekundy = 0)
    var scheduledAt: Date = Date()
    /// Dzień ("yyyy-MM-dd") i minuta od północy planowanej dawki – klucz w historii.
    var dayKey: String = ""
    var minute: Int = 0
    /// Kiedy użytkownik oznaczył dawkę
    var resolvedAt: Date = Date()
    var statusRaw: String = DoseStatus.taken.rawValue
    /// Ile tabletek odjęto z zapasu – cofnięcie oddaje dokładnie tyle.
    var pillsDeducted: Int = 0
    /// Nazwa i dawka w chwili zapisu – historia nie zmienia się po edycji leku.
    var medName: String = ""
    var dosage: String = ""
    var medication: Medication?

    init(scheduledAt: Date, dayKey: String, minute: Int, status: DoseStatus) {
        self.scheduledAt = scheduledAt
        self.dayKey = dayKey
        self.minute = minute
        self.resolvedAt = Date()
        self.statusRaw = status.rawValue
    }

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }
}
