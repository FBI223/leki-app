// SHARED – dodaj do wszystkich targetów
import Foundation
import SwiftData

/// Baza danych aplikacji: SwiftData (pod spodem SQLite) – leki, wersje planu i cała historia dawek.
/// Synchronizację przez iCloud włącza flaga `AppFeatures.iCloudSyncEnabled`.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    /// true, gdy w kodzie włączono iCloud i kontener z CloudKit utworzył się poprawnie.
    private(set) var usesICloud = false

    private init() {
        let schema = Schema([Medication.self, MedSchedule.self, DoseLog.self])

        if AppFeatures.iCloudSyncEnabled {
            // .automatic = pierwszy kontener iCloud z pliku .entitlements.
            // Wszystkie targety muszą mieć TEN SAM kontener i być zalogowane na to samo Apple ID.
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                self.container = container
                usesICloud = true
                return
            }
            print("⚠️ iCloud niedostępny – używam bazy lokalnej. Sprawdź uprawnienia iCloud w projekcie.")
        }

        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Nie można utworzyć bazy danych: \(error)")
        }
    }
}
