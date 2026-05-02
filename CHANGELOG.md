# Changelog

## 0.4.0 — 2026-05-02

Trip lifecycle, vehicle pairing, Bluetooth auto-detect, drawer navigation,
detailed AppLogger.

### Added
- **Trip card** as the main-screen primary surface. Big Start / Stop button,
  current vehicle label, live duration, GPS-active pulse indicator, and the
  source (manual vs Bluetooth).
- **Vehicles screen** (drawer → Vozidlá). Lists paired Bluetooth devices,
  attaches a vehicle label, and lets the driver toggle *Auto-start on
  connect* per device.
- **Auto-detect toggle** on the main screen. When ON, paired vehicles with
  *Auto-start* enabled trigger trip start/stop on Bluetooth A2DP/HFP
  connect/disconnect events.
- **Bluetooth A2DP/HFP listener** (native `BroadcastReceiver` + EventChannel
  in `MainActivity.kt`) plus a foreground re-poll on every app resume that
  back-stops missed broadcasts.
- **Disconnect grace period** (30 s) — multi-BT cars (headunit + OBD +
  handsfree dock) keep the trip running until the last known device drops
  off the network.
- **Drawer navigation menu**: Vehicles, Settings, Logs, *Send location*
  (now relabelled as a diagnostic tool, not a primary action).
- **AppLogger** — persistent ring buffer of app-level events (BT, trip
  lifecycle, send results, motion, toggles), merged into the Logs screen
  alongside Tracelet's SDK log.
- New trip / vehicle / locale strings in `app_sk.arb`, `app_cs.arb`,
  `app_en.arb`.
- `flutter_blue_classic`, `permission_handler`, `http` dependencies.
- Bluetooth runtime permissions (`BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`)
  declared in `AndroidManifest.xml`.

### Changed
- Tracking engine no longer auto-starts on app launch. `TripController`
  drives `engine.start/stop` so the GPS only burns battery during trips.
- `TraceletEngine.getCurrentPosition` and `start()` skip
  `requestLocationAuthorization` when the permission is already granted —
  no more spurious system-settings page redirections.
- `OsmAndSender` now ships positions over **HTTP GET** with query
  parameters (Traccar's OsmAnd decoder rejected our previous POST with an
  empty body and returned HTTP 400).
- "Začať jazdu" string changed to *Vozidlo stojí / Vozidlo v pohybe*.
- Status screen merges AppLogger and Tracelet logs (newest first), and
  has a *Copy to clipboard* icon for sharing.

### Notes / known limitations
- Background-while-process-killed BT detection still requires a
  manifest-declared receiver (planned 0.4.x). For now auto-detect works
  while the app process is alive; foregrounding the app re-polls and
  back-fills missed connect events.
- Devices must be **registered in Traccar** by `uniqueId` before positions
  are accepted — otherwise the server returns HTTP 400. Auto-registration
  via login is planned for 0.5.0.
- `flutter_blue_classic` v0.0.9 only enumerates bonded devices; profile
  proxies live in our native Kotlin layer.

## 0.3.1 — 2026-05-02

Slovak as default UI language + in-app language switcher.

### Added
- `Preferences.language` key (default `sk`) and a `Settings → Jazyk` tile
  with a Slovenčina / Čeština / English picker.
- Global `appLocale` `ValueNotifier<Locale>` in `main.dart` so a language
  change re-renders the whole app immediately (no restart needed).
- `languageLabel` ARB string in `app_sk.arb`, `app_cs.arb`, `app_en.arb`.

### Changed
- `MaterialApp` is now wrapped in a `ValueListenableBuilder<Locale>` and
  reads its `locale` from the persisted preference, defaulting to Slovak.

## 0.3.0 — 2026-05-02

Drops the commercial `flutter_background_geolocation` SDK in favour of
[`tracelet`](https://pub.dev/packages/tracelet) (Apache 2.0). No more $500
per-app license.

### Added
- `lib/tracking/tracelet_engine.dart` — `TraceletEngine implements TrackingEngine`,
  the new default engine (wired in `lib/tracking/engine.dart`).
- `lib/tracking/osmand_sender.dart` — custom HTTP layer that POSTs Traccar
  OsmAnd query-string parameters to `:5055`. Tracelet's built-in `HttpConfig`
  posts JSON, which the OsmAnd protocol does not accept; we bypass it.
  Includes a `SharedPreferences`-backed retry queue (FIFO, max 200 entries)
  for offline buffering — failed sends are flushed on the next successful
  send.
- `dispatchLocation(TrackedLocation)` method on the `TrackingEngine` interface.
  Each adapter decides how to ship a single location: `TraceletEngine` calls
  `OsmAndSender.send`, the (now-removed) `FbgEngine` would have used
  `BackgroundGeolocation.sync`.

### Removed
- `flutter_background_geolocation` from `pubspec.yaml` (and corresponding
  Gradle plugin / license meta-data stub from `AndroidManifest.xml`).
- `lib/tracking/fbg_engine.dart`. To restore: `git show v0.2.0:lib/tracking/fbg_engine.dart`
  and re-add the dependency.

### Notes
- Tracelet's `Tracelet.openBatterySettings()` opens the system Battery
  Optimization page directly — there is no native dialog wrapper like FBG's
  `DeviceSettings.showIgnoreBatteryOptimizations()`. Behaviour from the
  user's perspective is the same.
- `engine.sync()` is now a no-op for Tracelet. Per-location dispatch goes
  through `dispatchLocation`.

## 0.2.0 — 2026-05-02

Engine-pluggable tracking architecture. No user-visible behavior change; the
default engine is still `flutter_background_geolocation`. The point of 0.2.0
is that swapping to a different SDK in 0.3.0 (planned: `tracelet`, free + Apache 2.0)
is a one-line change in `lib/tracking/engine.dart`.

### Added
- `lib/tracking/tracking_engine.dart` — abstract `TrackingEngine` interface and
  engine-agnostic DTOs (`TrackedLocation`, `TrackingState`, `TrackingProviderState`,
  `TrackingAuthorizationStatus`, `HeadlessEvent`, `HeadlessEventType`).
- `lib/tracking/tracking_config.dart` — engine-agnostic `TrackingConfig` with
  primitive fields (accuracy, distance, intervals, heartbeat, stop detection,
  buffer, server URL, device id, OsmAnd body template).
- `lib/tracking/fbg_engine.dart` — `FbgEngine implements TrackingEngine` adapter
  that wraps `flutter_background_geolocation`. All translation between primitive
  config and `bg.Config / GeoConfig / AppConfig / HttpConfig / …` lives here.
- `lib/tracking/engine.dart` — single global `engine` singleton. Swap engines
  by changing one line.

### Changed
- `Preferences.geolocationConfig(bool)` → `Preferences.trackingConfig(bool)`,
  now returns `TrackingConfig` (engine-agnostic) instead of `bg.Config`.
- `LocationCache` `Location` model renamed to `CachedLocation`; `set()` now
  takes `TrackedLocation` instead of `bg.Location`.
- `geolocation_service.dart`, `configuration_service.dart`, `main_screen.dart`,
  `settings_screen.dart`, `quick_actions.dart`, `status_screen.dart` no longer
  import `flutter_background_geolocation` directly; they all go through `engine`.
- Email-log target changed from `support@traccar.org` to `support@starlogic.net`.

### Notes
- 0.3.0 will add `lib/tracking/tracelet_engine.dart` (Apache 2.0 alternative)
  plus a custom OsmAnd HTTP layer to replace `flutter_background_geolocation`'s
  `_locationTemplate` hack. Once it's in, `engine.dart` flips one line and the
  app no longer needs the $500 transistorsoft license.

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
