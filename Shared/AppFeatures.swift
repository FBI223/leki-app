// SHARED – wszystkie targety (iOS + Watch)
import Foundation

/// Przełączniki funkcji. Zmień wartość na `true`, żeby włączyć daną funkcję.
/// To jedyne miejsce w kodzie, które musisz edytować, gdy dokupisz konto developerskie.
///
/// Flaga włącza funkcję w kodzie, ale Apple wymaga też uprawnień (entitlements) w podpisie
/// aplikacji. Gotowe pliki są w folderze `Config/` – patrz README, sekcja „Płatne konto”.
/// Na darmowym koncie (Personal Team) zostaw wszystko na `false`, inaczej aplikacja
/// nie zainstaluje się na telefonie.
nonisolated enum AppFeatures {

    // MARK: iCloud

    /// Synchronizacja leków i historii między wszystkimi urządzeniami przez iCloud (CloudKit).
    ///
    /// Co zrobić, żeby włączyć:
    /// 1. Ustaw tu `true`.
    /// 2. W ustawieniach targetów ustaw Code Signing Entitlements na
    ///    `Config/LEKapp-Paid.entitlements` (iOS/Mac) i `Config/LekiWatch-Paid.entitlements` (zegarek)
    ///    – zawierają iCloud (CloudKit), Push Notifications i powiadomienia „time sensitive”.
    ///    Kontener w obu plikach musi być TEN SAM (zmień nazwę, jeśli zmienisz bundle ID).
    /// 3. Wszystkie urządzenia muszą być zalogowane na to samo Apple ID.
    /// Jeśli kontener iCloud się nie utworzy, aplikacja sama wróci do zapisu lokalnego.
    static let iCloudSyncEnabled = false

    // MARK: Alerty krytyczne

    /// Prawdziwe alerty krytyczne (przebijają wyciszenie i tryb „Nie przeszkadzać").
    ///
    /// Co zrobić, żeby włączyć:
    /// 1. Ustaw tu `true`.
    /// 2. Zdobądź zgodę Apple (formularz „Critical Alerts entitlement" na developer.apple.com),
    ///    a potem użyj plików `Config/*-Paid+Critical.entitlements` zamiast `*-Paid.entitlements`.
    ///
    /// Gdy jest `false`, leki oznaczone jako krytyczne działają w trybie „time sensitive"
    /// i dodatkowo ponawiają przypomnienie (patrz niżej).
    static let criticalAlertsEnabled = false

    /// Ponowienia dla leków krytycznych: po ilu minutach od planowanej godziny przypomnieć
    /// ponownie, jeśli dawka nie została oznaczona. Puste [] wyłącza ponowienia.
    static let criticalFollowUpMinutes: [Int] = [5, 10]

    // MARK: Powiadomienia

    /// Zegarek domyślnie dostaje powiadomienia z iPhone'a (lustrzane, gdy iPhone jest zablokowany).
    /// `true` = zegarek planuje własne (mogą się dublować z tymi z iPhone'a).
    static let watchSchedulesOwnReminders = false

    /// Na ile dni do przodu planujemy powiadomienia. Otwórz aplikację przynajmniej raz
    /// w tym okresie, żeby okno się przesunęło.
    static let schedulingWindowDays = 14

    /// iOS dopuszcza maksymalnie 64 oczekujące powiadomienia – zostawiamy zapas.
    static let maxScheduledNotifications = 60
}
