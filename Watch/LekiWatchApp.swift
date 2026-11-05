// watchOS – punkt wejścia aplikacji na zegarek (@main)
import SwiftUI
import SwiftData

@main
struct LekiWatchApp: App {
    init() {
        NotificationService.shared.configure()
        WatchSync.shared.activate()   // dane z iPhone'a (bez iCloud)
    }

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .tint(.teal)
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
