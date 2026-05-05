# Changelog

## 0.19.0 — 2026-05-05

Diagnostics, vehicle list, and login polish.

### Added
- **Permission status card** on MainScreen — shows location (when-in-use + always), activity recognition, Bluetooth and notification permission state at a glance, with a single "Obnoviť" button that re-asks for any that are missing.
- **Server health card** — pings the configured Backend + Traccar URLs and shows up/down status; helpful when a driver suspects "no jazdy syncing" turns out to be a network or DNS issue.
- **Session-dead banner** — when the backend refresh fails, MainScreen surfaces a tappable "Backend session vypršala" notice that jumps to login. Trips keep saving locally until re-paired.
- **Vehicles screen rework** — list view of paired vehicles with their last seen time, allowing quick re-pair / unpair without the QR flow.
- New "Hotovo" button on `TripDetailScreen` for explicit save-and-back instead of relying on the system back gesture.

### Changed
- l10n: 13 new strings added to `app_sk.arb`, `app_cs.arb`, `app_en.arb` for the items above.
- `LoginScreen` autofill hints + small layout tightening for one-handed entry.
- Server presets: only the `kAutoLogicServer` (api.autologic.sk) preset is exposed by default; legacy localhost / starlogic.net presets remain available via dev menu.

## 0.18.0 — 2026-05-05

Last-purpose chips in `TripFieldsEditor`: after a trip ends (or when
the editor opens for a finished trip), pulls the driver's most-used
purposes for that destination from `GET /api/v1/trips/last-purpose`
and renders them as `ActionChip`s above the static presets. Tap fills
the purpose textbox. Empty list (or auth/network failure) keeps the
existing preset row only — never blocks.

## 0.17.0 — 2026-05-05

Server URL move to `api.autologic.sk` + UX fixes.

### Changed
- **`kAutoLogicServer` preset** now points at `api.autologic.sk`
  (Backend `:8080`, Traccar admin `:8082`, OsmAnd `:5055`) instead of
  the dev-only `autologic.starlogic.net` hostnames. Cloudflare DNS in
  front of the new domain runs as DNS-only so the custom Traccar ports
  are reachable. Old preset name *"AutoLogic (Starlogic)"* renamed to
  just *"AutoLogic"*.
- **Auto-migration on startup**: any URL pref that still contains
  `autologic.starlogic.net` or `localhost` gets rewritten to the
  matching `api.autologic.sk` URL. Existing installs (and Auto Backup
  restores into fresh installs) now self-heal without the user having
  to dig through Settings → Server URL.

### Fixed
- **Logout flow** flips the auth gate to the `LoginScreen` immediately
  and runs Traccar / Backend revoke + local clear in the background
  with a 5 s HTTP timeout. Previously a misconfigured (or blocked)
  Server URL hung the logout button for two minutes — `Logout` looked
  unresponsive.
- **Auto-promote primary BT vehicle** even when multiple bonded BT
  devices are visible, by filtering out common accessory name
  patterns (`smartbox`, `obd`, `elm`, `headphone`, `airpods`, `watch`,
  `band`, `beacon`, …). The phone's actual head-unit is then the
  unique candidate and gets promoted automatically — driver no longer
  lands on a Vehicles screen with no radio selected after a reinstall.
- **`PermissionStatusCard` initState crash**: the inline `_items`
  initializer dereferenced `AppLocalizations.of(context)` from
  `initState`, which throws because inherited widgets aren't ready
  yet. Refactored to top-level `_PermItem` records that resolve
  labels at build time.
- **`PermissionStatusCard` auto-hides** when every permission is
  granted — the home screen no longer carries a "all good" card it
  can't act on. Card slot moved above the trip card so a denial is
  the first thing the driver sees on a fresh launch, not buried
  below other sections.

## 0.16.0 — 2026-05-05

UX features from the 2026-05-05 morning test (Batch 3b).

### Added
- **`LiveTripDistance`** ([lib/trip/live_trip_distance.dart](lib/trip/live_trip_distance.dart)) —
  global accumulator for the active trip's driven kilometres. Resets in
  `TripController.start`, fed by `TraceletEngine.dispatchLocation` on
  every GPS tick (Haversine sum-of-legs, rejects >10 km outliers from
  fix-loss). Exposes a `ValueNotifier<double>` for live UI updates.
- **Live `Tacho po` suggestion in `TripFieldsEditor`.** While a trip is
  running, the suggested end-odometer keeps ticking up as the driver
  moves (`Tacho pred + round(LiveTripDistance.km)`). Driver only has
  to confirm at the end rather than computing the delta. Manual edits
  still latch the field as for finished trips. `TripController.stop`
  also persists the live total instead of the start→end straight-line,
  fixing under-counts on curvy routes.
- **`PermissionStatusCard`** on `MainScreen` — compact card listing the
  five Drive-critical Android permissions (location while-in-use,
  location always, activity recognition, Bluetooth, notifications) with
  green-check / red-X status. Tapping a denied row requests it (or opens
  app settings if permanently denied). Re-evaluates on every app resume.
- **"Hotovo" button** at the bottom of `TripDetailScreen`. Auto-save
  already persists every edit on an 800 ms debounce — the button is
  pure navigation (`Navigator.pop`) but gives drivers an explicit "I'm
  done, go back to home" affordance.

## 0.15.2 — 2026-05-05

Hotfix from the 2026-05-05 morning test (Batch 3a — critical fixes).

### Fixed
- **App crash on swipe-up + auto-detect.** Tracelet's `LocationService`
  is a foreground service of type `location`, but our manifest only
  declared `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_CONNECTED_DEVICE`.
  Android 14+ throws `SecurityException` at FGS start without the
  matching `FOREGROUND_SERVICE_LOCATION` permission, killing the app.
  Visible whenever the user swipe-dismissed Drive and BT/AA then
  triggered an auto-trip from killed state. Added the missing
  `<uses-permission>` line.
- **Duplicate trip records on auto-start race.** `BluetoothWatcher`
  emits both broadcast events and foreground polls in quick succession;
  two callers were entering `TripController.start` before
  `tripState.active` flipped, producing two `Trip log: insert` rows
  per real trip start (observed: 4–6 ghost records per drive).
  Added a `_starting` re-entry flag that fast-paths the second caller.

### Added
- **Session-dead banner on `MainScreen`.** When backend access + refresh
  tokens are both dead, `BackendApi.sessionDeadNotifier` flips and the
  home screen shows an `errorContainer`-tinted card *"Backend session
  vypršala — klikni pre opätovné prihlásenie"*. Tap → `BackendApi.logout()`
  + `isAuthenticated.value = false`, which routes through the
  `LoginScreen` / QR-pair flow. Replaces the previous silent damper
  that just stopped logging 401s.

## 0.15.1 — 2026-05-04

### Added
- **Settings → Zmeniť heslo** — re-uses `SetPasswordScreen(skippable: false)`. Visible only when `BackendApi.isPaired`.

## 0.15.0 — 2026-05-04

Self-service password setup after pairing.

### Added
- `BackendApi.setPassword(newPassword)` — POST `/api/v1/auth/set-password`
  on the .NET backend (autologic-backend v0.13.0). Lets the paired driver
  set/change a password for later web-admin login.
- `SetPasswordScreen` ([lib/screens/set_password_screen.dart](lib/screens/set_password_screen.dart)) —
  shown right after a successful QR pairing (skippable). Validates ≥8 chars
  and that the confirm field matches. Re-usable from Settings later via
  `skippable: false`.
- After a successful pair (deep-link in `main.dart` _initLinks, in-app QR
  scan in `login_screen._scanQr`) the driver lands on `SetPasswordScreen`
  before reaching the home screen. "Preskočiť" is a no-op — driver can
  always set the password later.

## 0.14.0 — 2026-05-04

UX overhaul from the 2026-05-04 morning test (Batch 2).

### Added
- **`TripFieldsEditor`** ([lib/screens/widgets/trip_fields_editor.dart](lib/screens/widgets/trip_fields_editor.dart)) —
  reusable widget hosting the kniha-jázd form (driver autocomplete,
  purpose + chips, business/private, odometer pred/po). Auto-saves to
  SQLite with an 800 ms debounce, so no Save button is needed.
- **Inline editor on `MainScreen` during an active trip.** When a trip
  is running, the trip card now embeds `TripFieldsEditor` for the
  active record id directly under the GPS / vehicle status. Driver
  can fill in tacho pred and purpose without navigating into
  `TripDetailScreen`.
- **`VehicleRepository.setPrimaryAutoStart(mac)`** — promotes one
  paired BT device as the single auto-start trigger and clears
  `autoStartTrip` on every other vehicle. Stops the SmartBox + Karoq
  tug-of-war that caused trip flapping on real drives.

### Changed
- **`VehiclesScreen` + onboarding vehicles step** now render
  `RadioListTile` instead of `SwitchListTile` — there is exactly one
  primary auto-start vehicle at any time, and tapping the radio on a
  different car flips the others off.
- **`TripDetailScreen`** dropped its inline form and Save button; both
  responsibilities moved into `TripFieldsEditor`. Header card with
  vehicle / time / distance / addresses and the delete action stay.
- **`AppNotifications.consumeColdLaunch()`** captures the trip id from
  a notification tap that woke the app from a killed state. `MainScreen.initState`
  picks it up via `takePendingDeepLinkTripId` and pushes
  `TripDetailScreen` on the first frame — fixes the bug where tapping
  *"Doplň tacho"* on a fresh launch landed on the home screen with the
  Stop button instead of on the editable trip fields.

## 0.13.3 — 2026-05-04

Real-drive fixes from the 2026-05-04 morning test (Batch 1).

### Fixed
- **Backend token auto-refresh.** The access token expires after ~1 hour
  and there was no recovery, so `PositionSender` and `TripSync` started
  spamming HTTP 401 every 30 s for the rest of the day. New
  `BackendApi.getValidAccessToken()` checks `backendAccessExpiresAt` and
  triggers `refresh()` on demand (with a 30 s safety margin); a separate
  `BackendApi.refreshAfterUnauthorized()` is the explicit retry hook for
  401 responses. Added `BackendApi.isSessionDead` flag — once a refresh
  fails, both senders skip silently instead of flooding the log. The flag
  resets on next successful pair / login / refresh.
- **Android Auto disconnect → trip auto-stop.** `MonitorService`'s
  `CarConnection` observer now also emits on `NOT_CONNECTED`, and
  `BluetoothWatcher._onAndroidAutoDisconnected` applies the same 15 s
  flap grace + still-connected re-poll as the BT path. AA-only trips no
  longer hang open after the driver unplugs the cable.
- **`monitorServiceEnabled` defaulted to true on fresh install.**
  Previously the pref was missing on first launch; `MainActivity` read
  the absent key as "user opted out" and skipped starting `MonitorService`,
  so the very first jazda after onboarding never triggered. Toggling the
  Settings switch off/on used to be the only fix.

## 0.13.2 — 2026-05-04

Hotfix for 0.13.1: `backend_api_url` was missing from the
`SharedPreferencesWithCacheOptions.allowList`, so `Preferences.init`
threw `Invalid argument(s): backend_api_url is not included in the
PreferencesFilter allowlist` and the app froze on the splash screen.
Added the key to the allowlist.

## 0.13.1 — 2026-05-04

Fix: separate `backendApiUrl` preference for the AutoLogic Backend.

- Until now `Preferences.apiUrl` was reused for both Traccar (port 8082) and AutoLogic Backend (port 8080). On the Starlogic preset that meant `BackendApi.pair`, `PositionSender` and `TripSync` were sending to Traccar's admin REST, which doesn't host `/api/v1/auth/*` or `/api/v1/positions` — silent failure.
- New `Preferences.backendApiUrl` (default `http://autologic.starlogic.net:8080`). `BackendApi._baseUrl`, `PositionSender._flush`, `TripSync.pushPending` now read from it. `apiUrl` keeps its Traccar role.
- `ServerPreset` gains a `backendApiUrl` field. Existing installs get the new pref seeded on first launch.

## 0.13.0 — 2026-05-03

Parallel GPS sink to AutoLogic Backend — drives the Web Admin's trip-detail polyline.

### Added
- **`PositionSender`** (`lib/sync/position_sender.dart`) — in-memory buffer per active trip id; periodic flush every 30 s plus on-demand flush on trip stop. POSTs to `${backend}/api/v1/positions` (added in `autologic-backend` v0.11.0) with the bearer token already used for `auth/me` and `trips/sync`. Idempotent server-side keyed on the client-generated waypoint UUID.
- **`TraceletEngine.dispatchLocation`** now feeds each `TrackedLocation` into `PositionSender.enqueue(activeTrip, …)` before handing off to `OsmAndSender`. Failures here never block Traccar — the backend is a parallel sink.
- **`TripController.stop`** flushes `PositionSender` for the stopped trip before the post-stop `TripSync.pushPending`. The backend ends up with both the trip metadata and its waypoints by the time the Web Admin refreshes.
- **`main.dart`** starts the periodic flush timer at app init.

### Notes
- Buffer is **not persisted to SQLite**. App crashes mid-trip lose the in-flight waypoints since the last flush — Traccar still has them. Persistent queueing may land in 0.14.x if real-world usage shows the loss is meaningful.
- Backend has CORS `:8080 → web:4090` from v0.10.0 and the positions endpoints from v0.11.0; no further server work needed for this release.

## 0.12.0 — 2026-05-03

Background BT + Android Auto detection (the long-awaited "0.9.6" work) —
trips now auto-start even when the app is dismissed from recents, and
Android Auto projection acts as a second high-confidence trigger source
alongside Bluetooth.

### Added
- **`AutoLogicApplication`** + **`EngineChannels`** singleton — a
  process-level cached `FlutterEngine` (`FlutterEngineCache` keyed on
  `autologic_drive_main_engine`). The Dart isolate is initialised once
  at process start and survives `MainActivity.onDestroy`, so `BluetoothWatcher`
  keeps receiving connection events when the user has swiped the app away.
- **`MonitorService`** — always-on foreground service (notification
  channel `monitor_service`, importance MIN, priority MIN, lockscreen
  hidden). Hosts the BT broadcast receiver and an
  `androidx.car.app.connection.CarConnection` observer; both push events
  through `EngineChannels.emit(...)` to Dart. Started by `MainActivity.onCreate`.
- **Android Auto** as a trip trigger source. New `TripTriggerSource.androidAuto`
  enum value; new SK/EN/CS strings (`tripSourceAndroidAuto`). When AA
  projection comes online and no trip is active, Drive auto-starts a
  trip with the first paired auto-start vehicle (or anonymous if none).
- Manifest permissions `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`,
  service declaration with `foregroundServiceType="connectedDevice"`.
- Gradle deps `androidx.lifecycle:lifecycle-service:2.8.7`,
  `androidx.car.app:app:1.4.0`, `androidx.core:core-ktx:1.13.1`.

### Changed
- **`MainActivity`** stripped down to: provide cached engine, start
  `MonitorService`, and replay current BT state on resume via the new
  `poll_request` sentinel. All channel registration and the BT receiver
  moved to `EngineChannels` / `MonitorService`.
- Trip-source label rendering in `MainScreen` now uses a switch
  expression to render the AA case.

### Notes
- The persistent monitoring notification is intentionally minimum
  priority and hidden from the lock screen — visible only when the
  user pulls down the shade. It's the cost of background detection;
  Android requires foreground service status for any code that wants
  to react to BT broadcasts after the activity dies.
- Trip *stop* still relies on BT disconnect or manual action — AA
  disconnect is not yet wired as a stop trigger (most users have BT
  to the same car, which fires the existing stop path). Will revisit
  if real-world testing shows AA-only sessions stranding running trips.
- Trip-merging (collapse short BT gaps into one trip — courier use
  case) is still deferred; tracked in
  `project_autologic_drive_trip_merging_todo.md` memory.

## 0.11.1 — 2026-05-03

Identity continuity across reinstalls + better Traccar device naming.

### Added
- **Android Auto Backup** (`android:allowBackup="true"` + `backup_rules.xml`
  + `data_extraction_rules.xml`). SharedPreferences and the SQLite trip
  log are backed up to the user's Google account and automatically
  restored on a fresh install — so the random `Preferences.id` (used as
  the Traccar device `uniqueId`) survives reinstalls and the same Traccar
  device continues to receive positions instead of a duplicate appearing.
  Excludes `flutter_secure_storage` blob (device-bound BiometricLogin
  credentials are not meaningful on a different phone).
- **Better default Traccar device name**: registration now uses the
  phone's BT adapter name (e.g. *"Galaxy S24 Ultra"*) via a new
  `BluetoothHelper.deviceLabel()` bridge to native Kotlin. Falls back
  through `Settings.Global.DEVICE_NAME` (Android 12+) and `Build.MODEL`.
  Replaces the generic *"Drive · android"* placeholder. Still gets
  superseded by the primary vehicle label once the driver pairs a
  vehicle (existing behaviour).

### Notes
- The "stable identity from backend `userId`" approach is still the
  long-term plan (avoids the random ID drifting at all). It lands in
  0.12.x once the backend GPS proxy is ready and we control the device
  registration flow end-to-end. Auto Backup is the interim safety net.

## 0.11.0 — 2026-05-03

Trip-sync to AutoLogic Backend.

### Added
- **`TripSync`** ([lib/sync/trip_sync.dart](lib/sync/trip_sync.dart)) —
  pushes completed-but-unsynced trips to `POST /api/v1/trips/sync` on the
  backend, using the JWT obtained during pair / login. Acked trips flip
  their local `synced` flag to `true`; rejected ones stay queued and get
  retried on the next app start. Idempotent server-side on the
  client-generated trip UUID.
- **Post-stop hook** in `TripController.stop` calls `TripSync.pushPending()`
  fire-and-forget once the trip is finalised.
- **Startup retry** in `main.dart` flushes any trips that didn't reach the
  backend on stop (offline at the time, transient 5xx).
- **Settings → Synchronizácia s AutoLogic Backend** toggle (default ON)
  for users who want to keep the kniha jázd strictly local.

### Notes
- Backend endpoint `/api/v1/trips/sync` is being implemented in parallel
  by a separate agent against the spec at
  `C:\Projects\autologic-backend\docs\drive-integration-status.md`.
  Until that ships, sync calls will return non-2xx and trips will stay
  `synced=false` (visible only in CSV / local detail). No user-visible
  break — every other code path keeps working.
- The legacy direct Tracelet → Traccar GPS path on port 5055 is unchanged.
  GPS proxy through backend lands in 0.12.x.

## 0.10.0 — 2026-05-03

First integration with the AutoLogic Backend (.NET 10) — paves the way for
manager-issued QR onboarding without anyone touching Traccar's UI.

### Added
- **`BackendApi`** ([lib/auth/backend_api.dart](lib/auth/backend_api.dart)) —
  thin client for the new `/api/v1/auth/*` endpoints:
  `pair(token)` exchanges a one-time onboarding token for a JWT pair,
  `login(email, password)` is the email/password equivalent,
  `me()` fetches the authenticated user identity (id, tenantId, email, name,
  role) and caches it into `Preferences`,
  `refresh()` rotates the refresh token,
  `logout()` revokes it server-side and wipes local state.
- **Backend session prefs** in `Preferences`: `backend_access_token`,
  `backend_refresh_token`, `backend_access_expires_at`, `backend_user_id`,
  `backend_tenant_id`, `backend_role`.
- **Deep-link `token=` parameter** in `ConfigurationService.applyUri`.
  When the QR / `autologic-drive://configure?...` link carries a token,
  the app now exchanges it for a backend session and considers the driver
  authenticated automatically — no manual password step required.
  `applyUri` now returns `bool` (`true` when a backend pair succeeded).

### Changed
- **Auth gate** in `main.dart` flips `isAuthenticated` on either
  `TraccarApi.isLoggedIn` *or* `BackendApi.isPaired`.
- **Logout** in `main_screen` now also calls `BackendApi.logout()` so the
  driver is fully signed out of both worlds.
- **Login screen** dismisses itself directly after a successful QR pair
  instead of waiting for the user to type credentials.

### Notes
- Direct Traccar `/api/session` login still works for users who don't have
  a QR — the two paths are independent until a future release retires the
  Traccar cookie path entirely.
- Token refresh is implemented but not yet plugged into HTTP retries.

## 0.9.5 — 2026-05-03

Trip-quality + odometer UX fixes from first real-world test drive.

### Fixed
- **Ghost trips** (BT flap on parking lot, 0 m moved) are now dropped on
  stop even when no GPS fix was captured at the start. Drop trigger:
  start coord missing AND duration < 90 s. Previously these slipped
  through because the distance check was skipped on `null` distance.
- **Tacho po auto-fill self-poisoning**: typing the first digit of
  Tacho pred used to write that digit into Tacho po, which the controller
  listener immediately marked as "manually edited", freezing all
  subsequent auto-fills. Replaced the listener with a `TextField.onChanged`
  handler that only fires on real user input.

### Added
- **Tacho pred pre-fill** from the previous completed trip's Tacho po
  for the same vehicle. New trip detail opens with the start odometer
  already populated; driver only confirms or overrides.
- **Activity Recognition** permission (`android.permission.ACTIVITY_RECOGNITION`)
  added to manifest and requested as the third dialog in the onboarding
  location step. Without it Tracelet's motion detector falls back to a
  conservative always-sample mode and trip-start lags by tens of seconds.

### Deferred to 0.9.6
- Native manifest-declared BT BroadcastReceiver + persistent foreground
  monitoring service (so trips auto-start while the app process is
  killed). Larger native-Kotlin work than originally scoped — kept
  separate to avoid regressing the working BT flow before more testing.
- Trip-merging (collapse multiple BT sessions with short gaps into one
  trip — courier use case).

## 0.9.4 — 2026-05-03

UX polish + local-data retention.

### Changed
- **Onboarding welcome icon** no longer tinted with `colorScheme.onSurface`
  (was rendering as a flat white/black silhouette). Shows the AutoLogic
  icon in its native colours, matching the rest of the wizard steps.
- **Drawer header background** swapped from the near-white `#E8F0FE` to
  the saturated brand blue `#1A73E8`, matching the in-app icon palette.
- **Settings → Minimálna dĺžka jazdy** moved out of a `ListTile` subtitle
  into a full-width `Card` with the current value shown in the header
  and the slider at full height — was effectively invisible / clipped
  in the previous layout.

### Added
- **Settings → Uchovávať jazdy** retention dropdown
  (30 / 60 / 90 / 180 / 365 / Nikdy, default 60 days). On every app
  start `TripRepository.purgeOlderThan` deletes completed trips older
  than the threshold; active (unended) trips are always kept.

## 0.9.3 — 2026-05-03

Reverse-geocoded addresses in the trip log + minimum-trip-distance
guard against false-positive parking-lot trips.

### Added
- **Reverse-geocoded start/end addresses** in the trip log:
  - Stored in two new columns (`start_address`, `end_address`) on the
    `trips` table — schema bumped to v2 with an `ALTER TABLE ADD COLUMN`
    migration that preserves existing rows.
  - Resolved on demand via `geocoding: ^3.0.0` (Android `Geocoder` API,
    Slovak locale) and cached after the first resolve, so repeat opens
    of the trip detail are instant and the CSV export works offline.
  - Visible in **TripDetailScreen** (Štart / Cieľ rows under the time
    range), in the **Kniha jázd** list (compact `start → end` line in
    the subtitle), and in **CSV export** (two new columns *Štart adresa*
    and *Cieľ adresa* before the raw coordinates).
- **Settings → Minimálna dĺžka jazdy** slider (0–1000 m, default
  200 m). Trips with a straight-line start→end distance below the
  threshold are dropped on stop without a notification — silences the
  false-positives that come from shuffling around a parking spot or
  a brief A2DP reconnect.
- `TripController` now populates `distance_km` with the great-circle
  (Haversine) start→end distance on stop. Good enough for the
  odometer-end auto-fill in TripDetailScreen.

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
