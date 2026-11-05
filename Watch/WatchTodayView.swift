// watchOS
import SwiftUI
import SwiftData

struct WatchTodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Medication.name) private var meds: [Medication]
    @AppStorage(WatchSync.lastSyncKey) private var lastSync: Double = 0

    var body: some View {
        NavigationStack {
            let book = DoseBook(meds: meds)
            let doses = book.doses(on: .now)
            let taken = doses.filter { $0.log?.status == .taken }.count

            List {
                if doses.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        Gauge(value: Double(taken), in: 0...Double(max(doses.count, 1))) {
                            Text("Dziś")
                        } currentValueLabel: {
                            Text("\(taken)/\(doses.count)")
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(.teal)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(doses) { dose in
                        WatchDoseRow(dose: dose)
                    }
                }

                if AppFeatures.watchSyncEnabled {
                    Section {
                        Button {
                            WatchSync.shared.requestSnapshot()
                        } label: {
                            Label("Odśwież z iPhone'a", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } footer: {
                        Text(syncStatus)
                    }
                }
            }
            .navigationTitle("Leki")
        }
        .task {
            // Z iCloud zegarek ma własną, synchronizowaną bazę; bez niego to kopia danych z iPhone'a.
            if AppFeatures.iCloudSyncEnabled { PlanHistory.syncAll(context: context) }
            WatchSync.shared.requestSnapshot()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { WatchSync.shared.requestSnapshot() }
        }
    }

    private var emptyMessage: String {
        if AppFeatures.watchSyncEnabled && lastSync == 0 {
            return "Otwórz LEKapp na iPhonie, żeby przesłać leki na zegarek."
        }
        return "Brak leków na dziś"
    }

    private var syncStatus: String {
        guard lastSync > 0 else { return "Jeszcze nie zsynchronizowano z iPhone'em." }
        let date = Date(timeIntervalSince1970: lastSync)
        return "iPhone: \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct WatchDoseRow: View {
    let dose: ScheduledDose
    @Environment(\.modelContext) private var context

    var body: some View {
        let med = dose.medication
        let entry = dose.log

        Button {
            // Zmiana od razu na zegarku + wysłanie do iPhone'a, który zapisze ją w głównej bazie.
            if let entry {
                DoseEngine.undo(entry, context: context)
                WatchSync.shared.send(dose.key, status: nil)
            } else {
                DoseEngine.record(dose, status: .taken, context: context)
                WatchSync.shared.send(dose.key, status: .taken)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: med.symbol)
                    .foregroundStyle(med.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name).font(.headline).lineLimit(1)
                    Text(dose.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(dose.state() == .missed ? .orange : .secondary)
                }
                Spacer()
                Image(systemName: entry?.status == .taken ? "checkmark.circle.fill"
                      : entry?.status == .skipped ? "forward.circle.fill" : "circle")
                    .foregroundStyle(entry?.status == .taken ? Color.green : Color.secondary)
            }
        }
        .opacity(entry == nil ? 1 : 0.6)
        .sensoryFeedback(.success, trigger: entry?.statusRaw)
    }
}
