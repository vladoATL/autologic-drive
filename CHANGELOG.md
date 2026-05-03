# Changelog

## 0.9.2 — 2026-05-03

License-clean branding refresh.

### Changed
- Launcher icon (`assets/icon/autologic_icon.png`) replaced with the new
  `favicons/android-chrome-512x512.png` master from
  `starlogic-autologic/images/`. The previous icon was withdrawn for
  licensing reasons. `flutter_launcher_icons` regenerated all five
  Android density buckets.
- Notification small-icon (`ic_stat_notify`) re-rendered into all five
  drawables from the new alpha-only `autologic_icon-192.png` master.
- **Drawer header** now shows the **AutoLogic KJ logo** (square mark)
  on a brand-blue (`#E8F0FE`) background instead of a solid colour
  block with the *AutoLogic Drive* text — cleaner brand presentation
  on every drawer open.

### Added
- `assets/icon/autologic_kj_logo.png` asset (256×256) used by the
  drawer header.

## 0.9.1 — 2026-05-02

Trip-detail polish based on real-driving feedback.

### Added
- **App version footer** in the navigation drawer (`AutoLogic Drive · vX.Y.Z (build)`)
  via `package_info_plus`, so it's clear at a glance which version is in
  use during testing.
- **Driver autocomplete** in `TripDetailScreen` — typing into the driver
  field shows previously-used names (`SELECT DISTINCT driver_name`),
  with the full list as default suggestions when the field is empty.
  Useful when one phone is shared between family members.
- **Auto-fill end odometer**: filling in the start odometer pre-fills the
  end odometer with `start + round(distanceKm)`, picking up the GPS
  distance recorded during the trip. Stops auto-filling once the driver
  edits the end field manually, so corrections aren't overwritten.

## 0.9.0 — 2026-05-02

**Kniha jázd** — local trip log with the legally-required fields
(driver, purpose, business/private, odometer pre/po) so the records
satisfy Slovak / Czech tax-office requirements.

### Added
- `lib/trip/trip_record.dart` — `TripRecord` model with all the audit
  fields and `isComplete` heuristic.
- `lib/trip/trip_repository.dart` — sqflite-backed CRUD; one row per
  trip, indexed on `started_at` and `synced`. Schema version 1; future
  migrations go through `onUpgrade`.
- `TripController` now creates a `TripRecord` on `.start()` (capturing
  the start GPS fix from `LocationCache`) and stamps `endedAt` /
  `endLat,endLng` on `.stop()`. `activeRecordId` is exposed so
  notification deep links land on the right trip.
- `lib/screens/trip_detail_screen.dart` — edit screen for one trip:
  driver, purpose (with 6 preset chips), business/private toggle,
  odometer pre/po (manual int input — OCR is queued for 0.9.1), delete.
- `lib/screens/trips_screen.dart` — *Kniha jázd* drawer entry. List of
  all trips sorted newest-first, status badges (Aktívne / Nevyplnené /
  Vyplnené), filter chips (Všetky / Nevyplnené / Tento mesiac), and
  *Exportovať tento mesiac (CSV)* in the overflow menu.
- `lib/util/trip_csv_exporter.dart` — semicolon-CSV with UTF-8 BOM
  so Excel preserves diacritics. Columns match a typical kniha jázd
  layout. Goes through the OS share sheet via `share_plus`.
- Trip-lifecycle notifications now carry the trip ID as payload and
  deep-link to `TripDetailScreen` on tap; copy nudges the driver to
  fill the missing fields ("doplň tacho pred odjazdom" / "doplň účel
  a tacho po jazde").
- `Preferences.driverName` is captured from the Traccar `/api/session`
  response on every login and used as the default driver name on new
  trips. Per-trip override is editable in `TripDetailScreen`.

### Dependencies
- `sqflite ^2.3.3`, `path ^1.9.0`, `uuid ^4.5.1`, `share_plus ^10.0.0`,
  `path_provider ^2.1.4`.

### Notes
- **OCR for tachometer** is the only piece of the original 0.9.0 scope
  not yet implemented; manual integer input works fine and OCR will
  ship as 0.9.1 (Google ML Kit Text Recognition).
- **Backend sync** is deferred to 0.10+ once the custom backend exists.
  The persistence layer already has a `synced` flag so adding a sync
  worker later won't require a schema change.

## 0.8.1 — 2026-05-02

Tracking polish, log hygiene, notification fixes, and a `/simplify` pass.

### Changed
- **Tighter GPS sampling defaults** (`Preferences`): `distanceFilter`
  75 m → 20 m, `interval` 300 s → 60 s, accuracy `medium` → `high`.
  Traccar's straight-line route rendering now follows roads instead of
  cutting corners between sparse fixes. Migrated automatically for
  installs that hadn't intentionally raised these.
- **Disconnect grace** in `BluetoothWatcher` 30 s → 15 s. Real-world car
  BT drops both A2DP and headset within seconds of motor-off; the longer
  grace just delayed the "trip stopped" banner without rescuing real
  flaps.
- **BT log filter**: `BluetoothWatcher` skips logging events for devices
  that aren't trip-eligible (unpaired BT, paired-but-autoStart-off
  accessories like SmartBox dongles), so the Logs screen isn't drowned
  in irrelevant connect/disconnect chatter.
- **Tracelet foreground-service notification** is now Slovak — *"AutoLogic
  Drive — Zaznamenávam jazdu"* — and uses the new `ic_stat_notify` small
  icon (custom `ForegroundServiceConfig` with `channelId =
  autologic_tracking`). Replaces the upstream "Tracking location in
  background" English default.
- **Notification small icon**: replaced the launcher icon (which Android
  rendered as a big white square in the status bar) with a proper
  alpha-only silhouette `ic_stat_notify` rendered into all five
  Android density buckets from the 192 px master.
- **App launcher icon** updated to the new master in
  `assets/icon/autologic_icon.png`; `flutter_launcher_icons` regenerated
  every Android density.

### Fixed
- Trip-lifecycle notifications used ID `1`, the same range Tracelet's
  foreground-service notification claims. Bumped to `1001` to avoid the
  silent overwrite that suppressed our banner.
- `AppNotifications.init()` now requests Android 13+ runtime
  notification permission as a backstop for the skip-onboarding path.
- `OnboardingScreen` had a `PageController` leak (no `dispose()`).

### Refactor (`/simplify`)
- Extracted `lib/trip/vehicle_label_dialog.dart` (`promptVehicleLabel`)
  shared between `OnboardingScreen` and `VehiclesScreen`.
- `OnboardingScreen` bottom-sheet vehicle action is now an enum
  (`_VehicleAction.{rename, autoOn, autoOff, unlink}`) instead of magic
  strings.
- New ARB key `vehicleAutoStartOff` replaces a hardcoded SK fallback.
- `_refreshPermissionStatuses` and the four startup `init`s in `main()`
  use `Future.wait` for parallelism.

## 0.8.0 — 2026-05-02

First-launch onboarding wizard + trip-lifecycle notifications.

### Added
- `lib/screens/onboarding_screen.dart` — 7-step `PageView` wizard the
  driver walks once after the first login: welcome, location permission,
  battery optimization, notification permission (Android 13+), Bluetooth
  vehicle pairing, auto-detect toggle, summary. `Preferences.onboardingDone`
  remembers completion; *Settings → Spustiť úvodného sprievodcu* re-runs it.
- `lib/util/notifications.dart` — wrapper around
  `flutter_local_notifications` that posts a one-shot info notification on
  trip start (*"Jazda začala — Škoda Octavia, sledovanie polohy aktívne"*)
  and stop (*"Jazda ukončená — Škoda Octavia · 12 min"*). Hooked into
  `TripController.start` / `stop`.
- Permission status awareness in the wizard: each permission step now
  shows a green *Povolenie aktívne* badge instead of a *Povoliť* button
  when the OS already grants it, and re-checks on every app resume so a
  trip back to the system settings page reflects immediately.
- BT pairing step gains a bottom-sheet editor on tap of an already-paired
  device (header shows the BT device name + MAC; rows let the driver
  rename, toggle auto-start, or unlink).
- New strings in all three locales (sk/cs/en) for the wizard, notification
  bodies, the rename action, and the *Permission granted / Open settings*
  status block.

### Changed
- `MainActivity` extends `FlutterFragmentActivity` (already needed by
  `local_auth` in 0.7.0; nothing else touched here).
- `android/app/build.gradle.kts` enables core library desugaring +
  `desugar_jdk_libs:2.1.4` (required by `flutter_local_notifications`).
- Battery optimization step now opens the OS settings page directly via
  `app_settings`, not Tracelet's helper which was unreliable from a
  non-tracking state.

### Notes
- The persistent foreground-service notification while tracking is still
  generated by Tracelet itself; these new local notifications are
  informational nudges on top.

## 0.7.0 — 2026-05-02

Login screen polish + biometric quick-unlock.

### Added
- `lib/auth/biometric_login.dart` — wraps `local_auth` and stores
  email + password in `flutter_secure_storage` (Android Keystore-backed)
  when the driver opts into *Zapamätať prihlásenie*. Subsequent launches
  offer a fingerprint / PIN unlock that auto-replays the saved credentials
  through `TraccarApi.login`.
- *Show / hide password* toggle in the password field.
- *Zapamätať prihlásenie* checkbox (defaults to on).
- *Prihlásiť sa odtlačkom / PIN-om* button shown only when the device
  supports biometric and there are saved credentials from a previous login.
- New auth strings in all three locales.

### Changed
- Login screen body wrapped in `SingleChildScrollView` + `IntrinsicHeight`
  so opening the soft keyboard no longer triggers
  *BOTTOM OVERFLOWED BY N PIXELS*.
- `MainActivity` now extends `FlutterFragmentActivity` (required by
  `local_auth`'s `BiometricPrompt`) instead of `FlutterActivity`.
- *tripIdle* localised label changed from *Vozidlo stojí* to
  *Vozidlo pripravené na jazdu* (sk), *Vozidlo připravené k jízdě* (cs),
  *Ready to drive* (en).

## 0.6.0 — 2026-05-02

QR-code / deep-link onboarding so a fleet admin can hand a new driver
preconfigured server URL + email without typing.

### Added
- `lib/screens/qr_scan_screen.dart` — full-screen camera using
  `mobile_scanner`. Pops with the decoded string on first read.
- *Naskenovať QR* button on the login screen that pushes the scanner,
  feeds the result through `ConfigurationService.applyUri`, pre-fills
  the email field, and shows a *Konfigurácia načítaná z QR* toast.
- Three new query parameters supported by `ConfigurationService.applyUri`:
  `api` (Traccar REST URL), `osmand` (alias of legacy `url`), `email`
  (login pre-fill). Existing tracking-tunable params are unchanged.
- Localization for QR scan strings (sk/cs/en).

### Notes
- Onboarding link format:
  `autologic-drive://configure?api=<api-url>&osmand=<osmand-url>&email=<driver-email>`
- Companion admin tool lives in the
  [starlogic-autologic](https://github.com/vladoATL/autologic) repo at
  `tools/onboard.html` — a static page that takes the same three fields
  and produces a QR + shareable link. Password is **not** included in the
  link; the admin sends it through a separate channel (SMS, ...).

## 0.5.0 — 2026-05-02

Login flow + automatic device registration. The app no longer relies on
manually pre-registered Traccar devices — the user signs in with their
existing Traccar credentials, and the phone auto-registers itself as a
device under that account on first login.

### Added
- `lib/auth/traccar_api.dart` — minimal Traccar REST client (POST/GET/DELETE
  on `/api/session`, GET/POST `/api/devices`). Captures `JSESSIONID` from
  `Set-Cookie` and replays it on subsequent requests via the `Cookie`
  header. Cookie + email + userId persist in `Preferences`.
- `lib/screens/login_screen.dart` — entry-point screen with email + password
  fields. Auto-creates a device under the logged-in user (`uniqueId =
  Preferences.id`, `name = "Drive · android"`) right after a successful
  sign-in. Idempotent: looks the device up first via
  `GET /api/devices?uniqueId=...` and skips creation if already present.
- *Vytvoriť účet* button — placeholder snackbar for now (registration policy
  still TBD; Traccar self-registration is currently disabled server-side).
- `AuthGate` in `main.dart`: `MaterialApp.home` toggles between
  `LoginScreen` and `MainScreen` based on a global `isAuthenticated`
  `ValueNotifier`, so login/logout takes effect without rebuilding the
  whole app.
- Drawer **Odhlásiť sa** entry: stops any active trip, calls
  `DELETE /api/session`, clears the local cookie, and bounces back to the
  login screen.
- `ServerPreset.apiUrl` (port 8082 in dev, https in prod) plus
  `Preferences.apiUrl` migration for installs predating 0.5.0.
- New auth strings in all three locales.

### Changed
- `Preferences.init()` migrates pre-0.5.0 installs by seeding `apiUrl`
  with the AutoLogic preset if it's missing.
- Login email and trip toggles are logged in `AppLogger`, so the Status
  screen captures the full session lifecycle.

### Notes
- Dev server-side: `docker-compose.dev.yml` now binds Traccar's web port
  to `0.0.0.0:8082:8082` so the phone can reach `/api` over the LAN /
  router port-forward; the production deployment will sit behind Caddy
  on `:443`.

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
