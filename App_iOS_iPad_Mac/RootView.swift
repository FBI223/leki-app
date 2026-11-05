// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var meds: [Medication]

    /// Zmienia się, gdy zmieni się cokolwiek istotnego dla przypomnień
    /// (także po synchronizacji z innego urządzenia przez iCloud).
    private var signature: String {
        meds.map {
            "\($0.id)|\($0.name)|\($0.dosage)|\($0.timesRaw)|\($0.weekdaysRaw)|\($0.isCritical)|\($0.isActive)"
        }
        .sorted()
        .joined(separator: ";")
    }

    var body: some View {
        TabView {
            Tab("Dziś", systemImage: "sun.max.fill") { TodayView() }
            Tab("Leki", systemImage: "pills.fill") { MedicationListView() }
            Tab("Statystyki", systemImage: "chart.bar.xaxis") { StatsView() }
        }
        .task(id: signature) {
            await NotificationService.shared.requestAuthorization()
            await NotificationService.shared.reschedule(meds)
        }
    }
}
