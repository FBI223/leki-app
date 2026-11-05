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

    /// Godziny jako minuty od północy, np. "480,1200" = 8:00 i 20:00
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

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
    var logs: [DoseLog]? = []

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
    var isLowOnStock: Bool { tracksStock && pillsLeft <= refillThreshold }
}

@Model
final class DoseLog {
    var id: UUID = UUID()
    /// Planowana godzina dawki (sekundy = 0)
    var scheduledAt: Date = Date()
    /// Kiedy użytkownik oznaczył dawkę
    var resolvedAt: Date = Date()
    var statusRaw: String = DoseStatus.taken.rawValue
    var medication: Medication?

    init(scheduledAt: Date, status: DoseStatus) {
        self.scheduledAt = scheduledAt
        self.resolvedAt = Date()
        self.statusRaw = status.rawValue
    }

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }
}
