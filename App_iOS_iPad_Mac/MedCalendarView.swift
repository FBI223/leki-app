// iOS / iPadOS / macOS (zastępuje StatsView)
import SwiftUI
import SwiftData

/// Kalendarz miesięczny jak w aplikacji Kalendarz. Pod każdym dniem kolorowa kropka:
/// zielona = wszystko wzięte, pomarańczowa = część, czerwona = nic nie wzięte,
/// szara = zaplanowane. Kliknięty dzień pokazuje dawki i pozwala je oznaczyć (także wstecz).
struct MedCalendarView: View {
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var month: Date = MedCalendarView.startOfMonth(.now)
    @State private var selected: Date = Calendar.current.startOfDay(for: .now)

    private var cal: Calendar { Calendar.current }

    private static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? cal.startOfDay(for: date)
    }

    var body: some View {
        NavigationStack {
            let book = DoseBook(meds: meds)
            let days = gridDays()
            let stats = statsByDay(days, book: book)
            let today = cal.startOfDay(for: .now)
            let rate = DoseEngine.adherence(stats.values.filter { $0.date <= today })
            let selectedStat = stats[selected] ?? book.stat(on: selected)
            let selectedDoses = book.doses(on: selected)

            ScrollView {
                VStack(spacing: 14) {
                    calendarCard(days: days, stats: stats)

                    HStack(spacing: 12) {
                        StatTile(
                            title: "Regularność w miesiącu",
                            value: rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                            symbol: "target", tint: .green
                        )
                        StatTile(
                            title: "Seria dni",
                            value: "\(book.streak())",
                            symbol: "flame.fill", tint: .orange
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(selected, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.headline)
                            Spacer()
                            if selectedStat.total > 0 {
                                Text("Wzięte: \(selectedStat.taken) z \(selectedStat.total)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if selectedDoses.isEmpty {
                            Text(selected > today ? "Brak zaplanowanych dawek." : "Brak dawek tego dnia.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(selectedDoses) { dose in
                                DoseRow(dose: dose, interactive: selected <= today)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.screenBackground)
            .navigationTitle("Kalendarz")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Dziś") { goToToday() }
                }
            }
        }
    }

    // MARK: Kalendarz

    private func calendarCard(days: [Date?], stats: [Date: DayStat]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.title3).padding(8)
                }
                .accessibilityLabel("Poprzedni miesiąc")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.title3).padding(8)
                }
                .accessibilityLabel("Następny miesiąc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            HStack(spacing: 0) {
                ForEach(Array(weekdayHeader.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                    if let day = item {
                        dayCell(day, stat: stats[day] ?? DayStat(date: day))
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }

            legend
        }
        .card()
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 { shiftMonth(1) }
                else if value.translation.width > 40 { shiftMonth(-1) }
            }
        )
    }

    private func dayCell(_ day: Date, stat: DayStat) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)

        return Button {
            withAnimation(.snappy) { selected = day }
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                    .overlay(
                        Circle().stroke(Color.accentColor.opacity(0.5),
                                        lineWidth: (isToday && !isSelected) ? 1.5 : 0)
                    )
                Circle()
                    .fill(stat.state.color)
                    .frame(width: 7, height: 7)
                    .opacity(stat.state == .none ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.day().month(.wide))), \(stat.state.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            legendItem(.green, "Wszystko wzięte")
            legendItem(.orange, "Część wzięta")
            legendItem(.red, "Nic nie wzięte")
            legendItem(Color.secondary.opacity(0.5), "Zaplanowane")
        }
        .padding(.top, 4)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Dane i nawigacja

    private var weekdayHeader: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols   // indeks 0 = niedziela
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func gridDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            days.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return days
    }

    private func statsByDay(_ days: [Date?], book: DoseBook) -> [Date: DayStat] {
        var result: [Date: DayStat] = [:]
        for case let day? in days {
            result[day] = book.stat(on: day)
        }
        return result
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy) {
            month = next
            selected = cal.isDate(next, equalTo: .now, toGranularity: .month)
                ? cal.startOfDay(for: .now)
                : next
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            month = MedCalendarView.startOfMonth(.now)
            selected = cal.startOfDay(for: .now)
        }
    }
}

private extension DayState {
    var color: Color {
        switch self {
        case .none: return .clear
        case .upcoming: return Color.secondary.opacity(0.5)
        case .complete: return .green
        case .partial: return .orange
        case .missed: return .red
        }
    }

    var label: String {
        switch self {
        case .none: return "brak dawek"
        case .upcoming: return "zaplanowane"
        case .complete: return "wszystkie wzięte"
        case .partial: return "część wzięta"
        case .missed: return "nic nie wzięte"
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
