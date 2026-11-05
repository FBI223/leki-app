// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meds: [Medication]

    /// Zmienia się, gdy zmieni się cokolwiek istotnego dla przypomnień
    /// (także po synchronizacji z innego urządzenia przez iCloud).
    private var signature: String {
        meds.map {
            "\($0.id)|\($0.name)|\($0.dosage)|\($0.timesRaw)|\($0.weekdaysRaw)|\($0.isCritical)|\($0.isActive)|\($0.archivedAt?.timeIntervalSince1970 ?? 0)"
        }
        .sorted()
        .joined(separator: ";")
    }

    var body: some View {
        TabView {
            Tab("Dziś", systemImage: "sun.max.fill") { TodayView() }
            Tab("Kalendarz", systemImage: "calendar") { MedCalendarView() }
            Tab("Leki", systemImage: "pills.fill") { MedicationListView() }
        }
        .task(id: signature) {
            PlanHistory.syncAll(context: context)
            await NotificationService.shared.requestAuthorization()
            NotificationService.shared.scheduleRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Nowy dzień / powrót do aplikacji – przesuń okno zaplanowanych przypomnień.
            if phase == .active { NotificationService.shared.scheduleRefresh() }
        }
    }
}
