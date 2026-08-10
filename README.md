# Medicine Compass

Peer-to-peer people radar with real-time GPS navigation.

Home server API: `https://server.szadejko.net/api/kompas`

## Features

- **List** — paired people and last-activity status
- **Add** — your QR code + QR scanner (mutual pairing)
- **Edit** — display name / unpair
- **Info** — how it works + theme

GPS and server polling start only in the compass view for a selected person.

Polling by distance:

- under 100 m → every 2 s
- 100–1000 m → every 5 s
- over 1000 m → every 30 s

## Build

```bash
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release --target-platform android-arm64
flutter build ios --release --no-codesign
```

Server modules: [`home-server/`](home-server/).
