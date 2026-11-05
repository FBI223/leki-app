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
            #if DEBUG
            DemoData.seedIfRequested(context: context)
            #endif
            PlanHistory.syncAll(context: context)
            await NotificationService.shared.requestAuthorization()
            NotificationService.shared.scheduleRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Nowy dzień / powrót do aplikacji – przesuń okno zaplanowanych przypomnień.
            if phase == .active {
                NotificationService.shared.scheduleRefresh()
                WatchSync.shared.scheduleSnapshot()
            }
        }
    }
}

#if DEBUG
/// Dane przykładowe do testów: uruchom z argumentem `-demoData`
/// (Xcode: Product → Scheme → Edit Scheme → Run → Arguments). Działa tylko na pustej bazie.
private enum DemoData {
    static func seedIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoData"),
              ((try? context.fetchCount(FetchDescriptor<Medication>())) ?? 0) == 0 else { return }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let vitamin = Medication(name: "Witamina D", dosage: "1 kapsułka", times: [8 * 60, 20 * 60])
        vitamin.colorName = "orange"
        vitamin.symbol = "pill.fill"
        vitamin.createdAt = Calendar.current.startOfDay(for: yesterday)

        let heart = Medication(name: "Lek na serce", dosage: "5 mg", times: [9 * 60])
        heart.colorName = "red"
        heart.symbol = "heart.fill"
        heart.isCritical = true
        heart.tracksStock = true
        heart.pillsLeft = 9
        heart.createdAt = Calendar.current.startOfDay(for: yesterday)

        context.insert(vitamin)
        context.insert(heart)
        PlanHistory.sync(vitamin, context: context)
        PlanHistory.sync(heart, context: context)

        // Dzisiejsza poranna dawka witaminy już wzięta.
        DoseEngine.record(vitamin, dayKey: DayKey.string(for: .now), minute: 8 * 60,
                          scheduledAt: DoseEngine.date(minutes: 8 * 60, on: .now),
                          status: .taken, context: context)
    }
}
#endif
