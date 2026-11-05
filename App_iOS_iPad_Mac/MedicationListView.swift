// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct MedicationListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var newMed: Medication?
    @State private var pendingDelete: Medication?

    var body: some View {
        NavigationStack {
            let active = meds.filter { !$0.isArchived }
            let archived = meds.filter(\.isArchived)

            List {
                Section {
                    ForEach(active) { med in
                        NavigationLink {
                            MedicationEditView(med: med, isNew: false)
                        } label: {
                            MedicationRow(med: med)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Usuń", systemImage: "trash") { pendingDelete = med }
                                .tint(.red)
                        }
                    }
                }

                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { med in
                            MedicationRow(med: med)
                                .swipeActions(edge: .leading) {
                                    Button("Przywróć", systemImage: "arrow.uturn.backward") { restore(med) }
                                        .tint(.teal)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Usuń", systemImage: "trash") { pendingDelete = med }
                                        .tint(.red)
                                }
                                .contextMenu {
                                    Button("Przywróć", systemImage: "arrow.uturn.backward") { restore(med) }
                                    Button("Usuń z historią", systemImage: "trash", role: .destructive) {
                                        pendingDelete = med
                                    }
                                }
                        }
                    } header: {
                        Text("Archiwum")
                    } footer: {
                        Text("Leki w archiwum nie mają przypomnień, ale ich historia zostaje w kalendarzu. Przesuń w prawo, aby przywrócić.")
                    }
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
            .confirmationDialog(
                "Usunąć „\(pendingDelete?.name ?? "")”?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { med in
                if !med.isArchived {
                    Button("Przenieś do archiwum") { archive(med) }
                }
                Button("Usuń razem z historią", role: .destructive) { context.delete(med) }
            } message: { med in
                Text(med.isArchived
                     ? "Cała historia tego leku zniknie z kalendarza. Tego nie da się cofnąć."
                     : "Archiwum zachowuje historię dawek w kalendarzu. Usunięcie razem z historią jest nieodwracalne.")
            }
        }
    }

    private func archive(_ med: Medication) {
        med.archivedAt = .now
        PlanHistory.sync(med, context: context)
    }

    private func restore(_ med: Medication) {
        med.archivedAt = nil
        PlanHistory.sync(med, context: context)
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
                    if med.isArchived {
                        Text("w archiwum").font(.caption2).foregroundStyle(.secondary)
                    } else if !med.isActive {
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
                    if med.isLowOnStock && !med.isArchived {
                        Label("\(med.pillsLeft) szt.", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(med.isScheduledNow ? 1 : 0.5)
    }
}
