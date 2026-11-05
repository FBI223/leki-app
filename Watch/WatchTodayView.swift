// watchOS
import SwiftUI
import SwiftData

struct WatchTodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]

    var body: some View {
        NavigationStack {
            let doses = DoseEngine.doses(on: .now, for: meds)
            let taken = doses.filter { DoseEngine.log(for: $0)?.status == .taken }.count

            List {
                if doses.isEmpty {
                    Text("Brak leków na dziś")
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
    }
}

private struct WatchDoseRow: View {
    let dose: ScheduledDose
    @Environment(\.modelContext) private var context

    var body: some View {
        let med = dose.medication
        let entry = DoseEngine.log(for: dose)

        Button {
            if let entry {
                DoseEngine.undo(entry, context: context)
            } else {
                DoseEngine.record(med, at: dose.date, status: .taken, context: context)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: med.symbol)
                    .foregroundStyle(med.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name).font(.headline).lineLimit(1)
                    Text(dose.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: entry?.status == .taken ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry?.status == .taken ? Color.green : Color.secondary)
            }
        }
        .opacity(entry == nil ? 1 : 0.6)
        .sensoryFeedback(.success, trigger: entry?.statusRaw)
    }
}
