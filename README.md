# AutoLogic Drive

Mobile GPS tracker pre platformu **Starlogic AutoLogic**. Telefón vodiča funguje ako GPS-zariadenie a posiela polohu na náš Traccar-kompatibilný server `autologic.starlogic.net`.

Appka je fork-em open-source [`traccar/traccar-client`](https://github.com/traccar/traccar-client) (Apache 2.0). Upstream zmeny periodicky mergujeme cez `git fetch upstream && git merge upstream/main`.

## Status

`v0.1.0` — fork & rebrand baseline. Žiadne vodičske UI features (kniha jázd, Bluetooth pairing, auto-detekcia jazdy) — tie pribudnú vo Fáze 2 podľa [`DRIVE_APP_PLAN.md`](https://github.com/vladoATL/autologic/blob/main/docs/DRIVE_APP_PLAN.md).

## Setup

```bash
git clone https://github.com/vladoATL/autologic-drive.git
cd autologic-drive
flutter pub get
flutter gen-l10n
flutter run -d <android-device>
```

Pri prvom spustení appka vygeneruje náhodné 8-ciferné Device ID a nastaví server na **AutoLogic (Starlogic)**. Vodič v Settings → Server URL môže prepnúť na *Traccar Demo* alebo zadať vlastnú URL.

## Build & release

Debug APK:

```bash
flutter build apk --debug
```

Release APK vyžaduje:

1. Vlastnú **transistorsoft license** pre `flutter_background_geolocation` viazanú na `applicationId = net.starlogic.autologic.drive` ([shop.transistorsoft.com](https://shop.transistorsoft.com)). Bez nej beží release build v trial režime.
2. Keystore v `environment/key.properties` (mimo gitu).

```bash
flutter build apk --release
# alebo bundle pre Play Store:
flutter build appbundle --release
```

## License

Apache License 2.0 — viď [`LICENSE.txt`](LICENSE.txt) a [`NOTICE`](NOTICE).
