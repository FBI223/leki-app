# LEKapp

Przypominanie o lekach na iPhone, iPad, Mac i Apple Watch (SwiftUI + SwiftData).

## Struktura

| Folder | Zawartość |
| --- | --- |
| `Shared/` | wspólne dla wszystkich targetów: modele, baza, silnik dawek, powiadomienia, flagi |
| `App_iOS_iPad_Mac/` | ekrany Dziś, Kalendarz, Leki i formularz leku |
| `Watch/` | aplikacja na zegarek |
| `Config/` | gotowe pliki uprawnień na płatne konto (domyślnie niepodpięte) |

## Dane

- Baza to **SwiftData** (pod spodem SQLite): leki, wersje planu (`MedSchedule`) i cała historia dawek (`DoseLog`).
- Zmiana godzin, dni albo wstrzymanie leku działa **od teraz**. Przeszłe dni w kalendarzu liczą się według planu, który wtedy obowiązywał.
- Usunięcie leku pozwala przenieść go do **archiwum**: przypomnienia znikają, historia zostaje. Można też usunąć go razem z historią.
- Każdy wpis w historii zapamiętuje nazwę i dawkę leku z chwili zapisu oraz liczbę odjętych tabletek, więc cofnięcie oddaje dokładnie tyle samo.

## Przypomnienia

- Przypomnienia są jednorazowe, osobne dla każdej dawki, planowane na najbliższe `AppFeatures.schedulingWindowDays` dni.
- Oznaczenie dawki (także wcześniej) usuwa jej przypomnienie, ponowienia i drzemkę.
- Leki krytyczne mają ponowienia co `AppFeatures.criticalFollowUpMinutes` minut, dopóki dawka nie zostanie oznaczona.
- Okno przypomnień przesuwa się przy każdym otwarciu aplikacji. Jeśli nie otworzysz jej dłużej niż przez to okno, przypomnienia się skończą.

## Flagi (`Shared/AppFeatures.swift`)

| Flaga | Co robi | Wymaga |
| --- | --- | --- |
| `iCloudSyncEnabled` | synchronizacja leków i historii między urządzeniami (CloudKit) | płatne konto + `Config/*-Paid.entitlements` |
| `criticalAlertsEnabled` | alerty przebijające wyciszenie i „Nie przeszkadzać” | płatne konto + zgoda Apple + `Config/*-Paid+Critical.entitlements` |
| `watchSchedulesOwnReminders` | zegarek planuje własne przypomnienia | – |

Na darmowym koncie (Personal Team) zostaw `iCloudSyncEnabled` i `criticalAlertsEnabled` na `false`. Uprawnienia iCloud i alertów krytycznych blokują instalację na telefonie z darmowym kontem. Bez iCloud zegarek ma osobną, pustą bazę.

### Płatne konto: włączenie iCloud

1. W `AppFeatures.swift` ustaw `iCloudSyncEnabled = true`.
2. Target **LEKapp**: Build Settings → Code Signing Entitlements = `Config/LEKapp-Paid.entitlements`.
3. Target **LekiWatch Watch App**: Code Signing Entitlements = `Config/LekiWatch-Paid.entitlements`.
4. Jeśli zmienisz bundle ID, zmień też nazwę kontenera `iCloud.…` w obu plikach (musi być taka sama).
5. Dla synchronizacji w tle dodaj w iOS: Signing & Capabilities → Background Modes → Remote notifications.

Jeśli kontener iCloud się nie utworzy, aplikacja sama wróci do bazy lokalnej.
