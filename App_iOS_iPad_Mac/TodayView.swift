// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \Medication.name) private var meds: [Medication]

    var body: some View {
        NavigationStack {
            let book = DoseBook(meds: meds)
            let doses = book.doses(on: .now)
            let stat = book.stat(on: .now)
            let lowStock = meds.filter { $0.isScheduledNow && $0.isLowOnStock }

            ScrollView {
                VStack(spacing: 14) {
                    SummaryCard(stat: stat, streak: book.streak())

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
    let stat: DayStat
    let streak: Int

    /// Postęp liczony od wszystkich dzisiejszych dawek (także tych, które dopiero będą).
    private var progress: Double { stat.planned == 0 ? 0 : Double(stat.taken) / Double(stat.planned) }

    private var message: String {
        if stat.planned == 0 { return "Dziś wolne od leków 🎉" }
        if stat.taken == stat.planned { return "Wszystko wzięte. Świetnie! ✅" }
        if stat.missed > 0 { return "Nieoznaczone dawki: \(stat.missed)" }
        if stat.pending > 0 { return "Do wzięcia jeszcze: \(stat.pending)" }
        return "Na dziś to wszystko."
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: progress)
                VStack(spacing: 0) {
                    Text("\(stat.taken)/\(stat.planned)")
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

/// Wiersz jednej dawki – ekran Dziś i kalendarz.
struct DoseRow: View {
    let dose: ScheduledDose
    /// false dla przyszłych dni – dawki jeszcze nie można oznaczyć.
    var interactive = true
    @Environment(\.modelContext) private var context

    var body: some View {
        let med = dose.medication
        let state = dose.state()
        let isPastDay = Calendar.current.startOfDay(for: dose.date) < Calendar.current.startOfDay(for: .now)

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
                        .foregroundStyle(state == .missed ? Color.orange : Color.secondary)
                        .fontWeight(state == .missed ? .semibold : .regular)
                    let dosage = dose.log?.dosage.isEmpty == false ? dose.log!.dosage : med.dosage
                    if !dosage.isEmpty {
                        Text("·")
                        Text(dosage).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let note = note(state: state, isPastDay: isPastDay) {
                    Text(note.text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(note.color)
                }
            }

            Spacer(minLength: 8)

            if let entry = dose.log {
                Button {
                    withAnimation(.snappy) { DoseEngine.undo(entry, context: context) }
                } label: {
                    Image(systemName: entry.status == .taken ? "checkmark.circle.fill" : "forward.circle.fill")
                        .font(.title)
                        .foregroundStyle(entry.status == .taken ? Color.green : Color.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cofnij")
            } else if interactive {
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
        .opacity(dose.log == nil ? 1 : 0.65)
        .sensoryFeedback(.success, trigger: dose.log?.statusRaw)
    }

    private func note(state: DoseState, isPastDay: Bool) -> (text: String, color: Color)? {
        if let log = dose.log {
            let verb = log.status == .taken ? "Wzięte" : "Pominięte"
            return ("\(verb) \(log.resolvedAt.formatted(date: .abbreviated, time: .shortened))", .secondary)
        }
        if state == .missed && isPastDay { return ("Nie oznaczono", .red) }
        if !dose.isPlanned { return ("Poza planem", .secondary) }
        return nil
    }

    private func record(_ status: DoseStatus) {
        withAnimation(.snappy) {
            DoseEngine.record(dose, status: status, context: context)
        }
    }
}
