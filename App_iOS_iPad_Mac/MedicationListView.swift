// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct MedicationListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var newMed: Medication?

    var body: some View {
        NavigationStack {
            List {
                ForEach(meds) { med in
                    NavigationLink {
                        MedicationEditView(med: med, isNew: false)
                    } label: {
                        MedicationRow(med: med)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(meds[index]) }
                }
            }
            .overlay {
                if meds.isEmpty {
                    ContentUnavailableView(
                        "Brak leków",
                        systemImage: "pills",
                        description: Text("Dotknij +, aby dodać pierwszy lek.")
                    )
                }
            }
            .navigationTitle("Leki")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newMed = Medication()
                    } label: {
                        Label("Dodaj lek", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $newMed) { med in
                NavigationStack {
                    MedicationEditView(med: med, isNew: true)
                }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 620)
                #endif
            }
        }
    }
}

private struct MedicationRow: View {
    let med: Medication

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: med.symbol)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(med.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(med.name.isEmpty ? "Bez nazwy" : med.name).font(.headline)
                    if med.isCritical {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !med.isActive {
                        Text("wstrzymany").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(med.times, id: \.self) { minutes in
                        Text(DoseEngine.timeLabel(minutes))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(med.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(med.color)
                    }
                    if med.isLowOnStock {
                        Label("\(med.pillsLeft) szt.", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(med.isActive ? 1 : 0.5)
    }
}
