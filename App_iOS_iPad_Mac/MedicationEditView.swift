// iOS / iPadOS / macOS
import SwiftUI
import SwiftData

private struct TimeSlot: Identifiable, Equatable {
    let id = UUID()
    var date: Date
}

struct MedicationEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var med: Medication
    let isNew: Bool

    // Plan (godziny, dni, aktywność) edytujemy lokalnie i zapisujemy dopiero przy wyjściu –
    // dzięki temu powstaje jedna nowa wersja planu, a nie kilka podczas przewijania godzin.
    @State private var slots: [TimeSlot]
    @State private var weekdays: Set<Int>
    @State private var isActive: Bool

    init(med: Medication, isNew: Bool) {
        self.med = med
        self.isNew = isNew
        _slots = State(initialValue: med.times.map {
            TimeSlot(date: DoseEngine.date(minutes: $0, on: .now))
        })
        _weekdays = State(initialValue: med.weekdays)
        _isActive = State(initialValue: med.isActive)
    }

    private var times: [Int] { slots.map { DoseEngine.minutes(of: $0.date) } }
    private var hasDuplicateTimes: Bool { Set(times).count != times.count }
    private var canSave: Bool {
        !med.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !slots.isEmpty && !weekdays.isEmpty
    }

    var body: some View {
        Form {
            Section("Lek") {
                TextField("Nazwa leku", text: $med.name)
                TextField("Dawka, np. 1 tabletka, 500 mg", text: $med.dosage)
            }

            Section("Wygląd") {
                colorPicker
                symbolPicker
            }

            Section {
                ForEach($slots) { $slot in
                    DatePicker("Godzina", selection: $slot.date, displayedComponents: .hourAndMinute)
                }
                .onDelete { slots.remove(atOffsets: $0) }

                Button {
                    slots.append(TimeSlot(date: DoseEngine.date(minutes: 12 * 60, on: .now)))
                } label: {
                    Label("Dodaj godzinę", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Godziny przyjmowania")
            } footer: {
                if slots.isEmpty {
                    Text("Dodaj co najmniej jedną godzinę.").foregroundStyle(.red)
                } else if hasDuplicateTimes {
                    Text("Powtórzone godziny zostaną zapisane raz.").foregroundStyle(.orange)
                } else if !isNew {
                    Text("Zmiana godzin, dni lub wstrzymanie leku obowiązuje od teraz – historia w kalendarzu się nie zmienia.")
                }
            }

            Section("Dni tygodnia") {
                weekdayChips
            }

            Section {
                Toggle(isOn: $med.isCritical) {
                    Label("Lek krytyczny", systemImage: "bell.badge.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(criticalFooter)
            }

            Section("Zapas leku") {
                Toggle("Śledź ilość tabletek", isOn: $med.tracksStock.animation())
                if med.tracksStock {
                    Stepper("Zostało: \(med.pillsLeft)", value: $med.pillsLeft, in: 0...999)
                    Stepper("Tabletek na dawkę: \(med.pillsPerDose)", value: $med.pillsPerDose, in: 1...10)
                    Stepper("Ostrzegaj przy: \(med.refillThreshold)", value: $med.refillThreshold, in: 1...60)
                }
            }

            Section("Notatki") {
                TextField("Np. po jedzeniu, popić wodą", text: $med.notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            if !isNew {
                Section {
                    Toggle("Aktywny", isOn: $isActive)
                } footer: {
                    Text("Wstrzymany lek nie wysyła przypomnień na żadnym urządzeniu. Wcześniejsza historia zostaje.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nowy lek" : "Edytuj lek")
        .onDisappear {
            if !isNew { commitPlan() }
        }
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        med.name = med.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        med.createdAt = Date()
                        context.insert(med)
                        commitPlan()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var criticalFooter: String {
        var text = "Lek krytyczny jest wyróżniony i ma ponowne przypomnienia, jeśli dawka nie zostanie oznaczona."
        if AppFeatures.criticalAlertsEnabled {
            text += " Alert krytyczny przebija tryb Nie przeszkadzać i wyciszenie."
        } else {
            text += " Prawdziwe alerty krytyczne (przebijające wyciszenie) włącza się flagą w AppFeatures.swift – wymagają zgody Apple."
        }
        return text
    }

    /// Zapisuje plan i tworzy nową wersję w historii, jeśli coś się zmieniło.
    private func commitPlan() {
        if !slots.isEmpty { med.times = times }   // pustej listy godzin nie zapisujemy
        if !weekdays.isEmpty { med.weekdays = weekdays }
        med.isActive = isActive
        PlanHistory.sync(med, context: context)
        try? context.save()
    }

    // MARK: Elementy formularza

    private var colorPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MedPalette.colors) { item in
                    Circle()
                        .fill(item.color.gradient)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if med.colorName == item.name {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { med.colorName = item.name }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
            ForEach(MedPalette.symbols, id: \.self) { name in
                let selected = med.symbol == name
                Image(systemName: name)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? med.color : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture { med.symbol = name }
            }
        }
        .padding(.vertical, 4)
    }

    private var weekdayChips: some View {
        let symbols = Calendar.current.shortWeekdaySymbols   // indeks 0 = niedziela
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = weekdays.contains(weekday)
                Text(symbols[weekday - 1])
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? med.color : Color.secondary.opacity(0.15), in: Capsule())
                    .onTapGesture {
                        if on {
                            if weekdays.count > 1 { weekdays.remove(weekday) }   // min. jeden dzień
                        } else {
                            weekdays.insert(weekday)
                        }
                    }
            }
        }
    }
}
