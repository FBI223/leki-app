// iOS / iPadOS / macOS
import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query(sort: \DoseLog.resolvedAt, order: .reverse) private var logs: [DoseLog]
    @State private var range = 7

    var body: some View {
        NavigationStack {
            let days = DoseEngine.history(days: range, meds: meds)
            let taken = days.reduce(0) { $0 + $1.taken }
            let total = days.reduce(0) { $0 + $1.total }
            let rate = total == 0 ? 0 : Double(taken) / Double(total)

            ScrollView {
                VStack(spacing: 14) {
                    Picker("Zakres", selection: $range) {
                        Text("7 dni").tag(7)
                        Text("30 dni").tag(30)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        StatTile(title: "Regularność",
                                 value: rate.formatted(.percent.precision(.fractionLength(0))),
                                 symbol: "target", tint: .green)
                        StatTile(title: "Seria dni",
                                 value: "\(DoseEngine.streak(meds: meds))",
                                 symbol: "flame.fill", tint: .orange)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dawki dzień po dniu").font(.headline)
                        Chart {
                            ForEach(days) { day in
                                BarMark(x: .value("Dzień", day.date, unit: .day),
                                        y: .value("Liczba", day.taken))
                                    .foregroundStyle(by: .value("Status", "Wzięte"))
                                BarMark(x: .value("Dzień", day.date, unit: .day),
                                        y: .value("Liczba", day.total - day.taken))
                                    .foregroundStyle(by: .value("Status", "Niewzięte"))
                            }
                        }
                        .chartForegroundStyleScale(["Wzięte": Color.green, "Niewzięte": Color.red.opacity(0.65)])
                        .chartLegend(position: .bottom)
                        .frame(height: 220)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ostatnia aktywność").font(.headline)
                        let recent = logs.filter { $0.medication != nil }.prefix(12)
                        if recent.isEmpty {
                            Text("Brak wpisów – oznacz pierwszą dawkę w zakładce Dziś.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(recent)) { log in
                            HStack {
                                Image(systemName: log.status == .taken ? "checkmark.circle.fill" : "forward.circle.fill")
                                    .foregroundStyle(log.status == .taken ? Color.green : Color.gray)
                                Text(log.medication?.name ?? "")
                                Spacer()
                                Text(log.resolvedAt, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .card()
                }
                .padding()
            }
            .background(Color.screenBackground)
            .navigationTitle("Statystyki")
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value).font(.title.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}
