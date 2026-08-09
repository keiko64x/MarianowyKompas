# Szadejkompas

Radar osób peer-to-peer z nawigacją GPS w czasie rzeczywistym.

Aplikacja Flutter komunikuje się z domowym serwerem Node.js:

`https://server.szadejko.net/api/kompas`

## Zakładki

- **Lista** — sparowane osoby i status ostatniej aktywności
- **Dodaj** — Twój kod QR + skaner QR (dwustronne parowanie)
- **Edytuj** — zmiana nazwy wyświetlanej / odparowanie
- **Info** — opis mechaniki i motyw

GPS oraz odpytywanie serwera włączają się **dopiero** po wejściu w widok kompasu wybranej osoby. Interwał zależy od dystansu (Haversine): `>1 km` → 60 s, `100–1000 m` → 10 s, `<100 m` → 5 s.

## Budowanie APK

```bash
flutter pub get
flutter build apk --target-platform android-arm64
```

Moduły serwera: katalog [`home-server/`](home-server/).
