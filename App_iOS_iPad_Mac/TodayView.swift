// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \Medication.name) private var meds: [Medication]

    var body: some View {
        NavigationStack {
            let doses = DoseEngine.doses(on: .now, for: meds)
            let taken = doses.filter { DoseEngine.log(for: $0)?.status == .taken }.count
            let lowStock = meds.filter { $0.isActive && $0.isLowOnStock }

            ScrollView {
                VStack(spacing: 14) {
                    SummaryCard(taken: taken, total: doses.count, streak: DoseEngine.streak(meds: meds))

                    ForEach(lowStock) { med in
                        LowStockBanner(med: med)
                    }

                    if doses.isEmpty {
                        ContentUnavailableView(
                            "Brak leków na dziś",
                            systemImage: "pills",
                            description: Text("Dodaj pierwszy lek w zakładce Leki.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(doses) { dose in
                            DoseRow(dose: dose)
                        }
                    }
                }
                .padding()
            }
            .background(Color.screenBackground)
            .navigationTitle("Dziś")
        }
    }
}

private struct SummaryCard: View {
    let taken: Int
    let total: Int
    let streak: Int

    private var progress: Double { total == 0 ? 0 : Double(taken) / Double(total) }

    private var message: String {
        if total == 0 { return "Dziś wolne od leków 🎉" }
        if taken == total { return "Wszystko wzięte. Świetnie! ✅" }
        return "Do wzięcia jeszcze: \(total - taken)"
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: progress)
                VStack(spacing: 0) {
                    Text("\(taken)/\(total)")
                        .font(.title2.bold().monospacedDigit())
                    Text("dziś")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.headline)
                Label("Seria: \(streak) \(streak == 1 ? "dzień" : "dni")", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .card(padding: 18)
    }
}

private struct LowStockBanner: View {
    let med: Medication

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kończy się: \(med.name)").font(.subheadline.weight(.semibold))
                Text("Zostało \(med.pillsLeft) szt. Pora uzupełnić zapas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 12)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.orange.opacity(0.4)))
    }
}

struct DoseRow: View {
    let dose: ScheduledDose
    @Environment(\.modelContext) private var context

    var body: some View {
        let med = dose.medication
        let entry = DoseEngine.log(for: dose)
        let overdue = entry == nil && dose.date < .now

        HStack(spacing: 14) {
            Image(systemName: med.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(med.color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(med.name).font(.headline)
                    if med.isCritical {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                HStack(spacing: 6) {
                    Text(dose.date, format: .dateTime.hour().minute())
                        .foregroundStyle(overdue ? Color.orange : Color.secondary)
                        .fontWeight(overdue ? .semibold : .regular)
                    if !med.dosage.isEmpty {
                        Text("·")
                        Text(med.dosage)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let entry {
                Button {
                    withAnimation(.snappy) { DoseEngine.undo(entry, context: context) }
                } label: {
                    Image(systemName: entry.status == .taken ? "checkmark.circle.fill" : "forward.circle.fill")
                        .font(.title)
                        .foregroundStyle(entry.status == .taken ? Color.green : Color.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cofnij")
            } else {
                HStack(spacing: 12) {
                    Button { record(.skipped) } label: {
                        Image(systemName: "forward.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Pomiń")

                    Button { record(.taken) } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.title)
                            .foregroundStyle(med.color)
                    }
                    .accessibilityLabel("Wzięte")
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 12)
        .opacity(entry == nil ? 1 : 0.6)
        .sensoryFeedback(.success, trigger: entry?.statusRaw)
    }

    private func record(_ status: DoseStatus) {
        withAnimation(.snappy) {
            DoseEngine.record(dose.medication, at: dose.date, status: status, context: context)
        }
    }
}
