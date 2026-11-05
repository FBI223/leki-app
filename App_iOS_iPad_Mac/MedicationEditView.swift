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
    @State private var slots: [TimeSlot]

    init(med: Medication, isNew: Bool) {
        self.med = med
        self.isNew = isNew
        _slots = State(initialValue: med.times.map {
            TimeSlot(date: DoseEngine.date(minutes: $0, on: .now))
        })
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
            }

            Section("Dni tygodnia") {
                weekdayChips
            }

            Section {
                Toggle(isOn: $med.isCritical) {
                    Label("Alert krytyczny", systemImage: "bell.badge.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Alert krytyczny przebija tryb Nie przeszkadzać i wyciszenie. Wymaga zgody Apple dla aplikacji oraz zgody użytkownika w ustawieniach powiadomień.")
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
                    Toggle("Aktywny", isOn: $med.isActive)
                } footer: {
                    Text("Wstrzymany lek nie wysyła przypomnień na żadnym urządzeniu.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nowy lek" : "Edytuj lek")
        .onChange(of: slots) { _, newValue in
            med.times = newValue.map { DoseEngine.minutes(of: $0.date) }
        }
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        med.createdAt = Date()
                        context.insert(med)
                        dismiss()
                    }
                    .disabled(med.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
        return HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                let on = med.weekdays.contains(weekday)
                Text(symbols[weekday - 1])
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? med.color : Color.secondary.opacity(0.15), in: Capsule())
                    .onTapGesture {
                        var days = med.weekdays
                        if on {
                            if days.count > 1 { days.remove(weekday) }   // min. jeden dzień
                        } else {
                            days.insert(weekday)
                        }
                        med.weekdays = days
                    }
            }
        }
    }
}
