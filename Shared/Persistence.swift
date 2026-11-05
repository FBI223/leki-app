// SHARED – dodaj do wszystkich targetów
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([Medication.self, DoseLog.self])
        // .automatic = pierwszy kontener iCloud z Signing & Capabilities.
        // Wszystkie targety muszą mieć TEN SAM kontener iCloud (np. iCloud.com.twojadomena.leki)
        // i być zalogowane na to samo Apple ID – wtedy dane synchronizują się same.
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Nie można utworzyć ModelContainer: \(error)")
        }
    }
}
