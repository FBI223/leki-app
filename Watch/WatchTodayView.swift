// watchOS
import SwiftUI
import SwiftData

struct WatchTodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]

    var body: some View {
        NavigationStack {
            let book = DoseBook(meds: meds)
            let doses = book.doses(on: .now)
            let taken = doses.filter { $0.log?.status == .taken }.count

            List {
                if doses.isEmpty {
                    Text(AppFeatures.iCloudSyncEnabled
                         ? "Brak leków na dziś"
                         : "Brak leków na dziś. Bez synchronizacji iCloud zegarek ma osobną listę leków.")
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
            }
            .navigationTitle("Leki")
        }
        .task { PlanHistory.syncAll(context: context) }
    }
}

private struct WatchDoseRow: View {
    let dose: ScheduledDose
    @Environment(\.modelContext) private var context

    var body: some View {
        let med = dose.medication
        let entry = dose.log

        Button {
            if let entry {
                DoseEngine.undo(entry, context: context)
            } else {
                DoseEngine.record(dose, status: .taken, context: context)
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
