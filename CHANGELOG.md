# Changelog

## 0.1.0 — 2026-05-02

Initial fork & rebrand of [`traccar/traccar-client`](https://github.com/traccar/traccar-client) v9.7.18 as **AutoLogic Drive**.

### Changed
- App identity: `name = autologic_drive`, version reset to `0.1.0+1`, `applicationId = net.starlogic.autologic.drive`, `android:label = "AutoLogic Drive"`.
- Default server URL: `http://autologic.starlogic.net:5055` (Traccar OsmAnd-protokol port).
- Theme: light/dark schemes seeded from brand `#1A1A1A`.
- Settings → Server URL: changed from free-text dialog to preset bottom-sheet with **AutoLogic (Starlogic)**, **Traccar Demo**, and **Custom** options (`lib/server_presets.dart`).
- Android deep-link scheme `org.traccar.client` → `net.starlogic.autologic.drive`.

### Removed
- Firebase stack: `firebase_core`, `firebase_messaging`, `firebase_analytics`, `firebase_crashlytics` dependencies, `firebase_options.dart`, `push_service.dart`, `firebase.json`, `google-services.json`, plus Gradle plugins and all `FirebaseCrashlytics.instance.log(...)` calls.
- `rate_my_app` dependency and rating dialog.
- `flutter_background_geolocation` upstream license JWT (was bound to `org.traccar.client`). Debug build runs in trial mode; release needs a new licence purchased for our `applicationId`.

### Added
- `lib/server_presets.dart` — `ServerPreset` model + preset list.
- Slovak localization (`lib/l10n/app_sk.arb`); Czech (`app_cs.arb`) was already present upstream. `l10n.yaml` preferred locales: `[sk, cs, en]`.
- Branding scaffolding for `flutter_launcher_icons` (icon PNG generation pending — needs `assets/icon/autologic_icon.png`).
- `NOTICE` file (Apache 2.0 attribution to Traccar).

### Notes / risks
- Release build of `flutter_background_geolocation` requires a valid transistorsoft licence keyed to `net.starlogic.autologic.drive`. Manifest stub is commented out in `AndroidManifest.xml`.
- App icon: still using default Flutter launcher icon. To finalise, render `C:\Projects\starlogic-autologic\images\autologic_icon.svg` to `assets/icon/autologic_icon.png` (1024×1024) and run `dart run flutter_launcher_icons`.
