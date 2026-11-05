// iOS / iPadOS / macOS – punkt wejścia aplikacji (@main)
import SwiftUI
import SwiftData

@main
struct LekiApp: App {
    init() {
        NotificationService.shared.configure()
        WatchSync.shared.activate()   // iPhone → zegarek (bez iCloud); na Macu nic nie robi
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.teal)
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
