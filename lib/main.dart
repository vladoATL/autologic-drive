import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:autologic_drive/geolocation_service.dart';
import 'package:autologic_drive/password_service.dart';
import 'package:autologic_drive/quick_actions.dart';
import 'package:autologic_drive/trip/bluetooth_helper.dart';
import 'package:autologic_drive/trip/bluetooth_watcher.dart';
import 'package:autologic_drive/trip/trip_controller.dart';
import 'package:autologic_drive/trip/trip_repository.dart';
import 'package:autologic_drive/trip/vehicle_repository.dart';
import 'package:autologic_drive/util/app_logger.dart';
import 'package:autologic_drive/util/notifications.dart';

import 'auth/backend_api.dart';
import 'auth/traccar_api.dart';
import 'l10n/app_localizations.dart';
import 'main_screen.dart';
import 'preferences.dart';
import 'configuration_service.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/set_password_screen.dart';
import 'sync/position_sender.dart';
import 'sync/trip_sync.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

const _seedColor = Color(0xFF1A1A1A);

/// Globálny holder UI jazyka. Settings → Language ho prepisuje, MaterialApp
/// počúva cez `ListenableBuilder` a okamžite prerendruje.
final ValueNotifier<Locale> appLocale = ValueNotifier<Locale>(const Locale('sk'));

/// Drives the AuthGate to switch between LoginScreen and MainScreen without
/// rebuilding the whole app.
final ValueNotifier<bool> isAuthenticated = ValueNotifier<bool>(false);

/// Forces the onboarding wizard to re-appear (e.g. when the user re-runs it
/// from Settings). Pre-checked at startup against `Preferences.onboardingDone`.
final ValueNotifier<bool> needsOnboarding = ValueNotifier<bool>(false);

/// Re-run device registration for the current `Preferences.id`. Pulls the
/// label from the primary vehicle if one is set, otherwise falls back to
/// the BT adapter name (same precedence as `LoginScreen._registerDevice`).
/// No-op when not logged into Traccar.
Future<void> _ensureTraccarDevice() async {
  if (!TraccarApi.isLoggedIn) return;
  final uniqueId = Preferences.instance.getString(Preferences.id);
  if (uniqueId == null || uniqueId.isEmpty) return;
  // Lazy-import via top-level reference to avoid pulling Vehicles into
  // main.dart's import graph just for this one fallback.
  String? name;
  try {
    name = await BluetoothHelper.deviceLabel();
  } catch (_) {}
  name ??= 'Drive · android';
  try {
    await TraccarApi.ensureDevice(name: name, uniqueId: uniqueId);
    await VehicleRepository.pullDeviceNameFromServer();
  } catch (e) {
    AppLogger.warn('ensureTraccarDevice on cold-start failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();
  appLocale.value = Locale(
    Preferences.instance.getString(Preferences.language) ?? 'sk',
  );
  AppNotifications.navigatorKey = navigatorKey;
  // Cold-launch notification tap: pre-load the trip id so MainScreen can
  // immediately push TripDetailScreen on first frame.
  unawaited(AppNotifications.consumeColdLaunch());
  // PasswordService.migrate, GeolocationService.init, AppNotifications.init
  // and TripController.restore all read from `Preferences` (already done) but
  // don't depend on each other — run them concurrently to shave cold-start.
  await Future.wait([
    PasswordService.migrate(),
    GeolocationService.init(),
    AppNotifications.init(),
    TripController.restore(),
  ]);
  BluetoothWatcher.start();
  // Fire-and-forget: prune trips older than the configured retention window.
  // Active (unended) trips are always kept.
  unawaited(TripRepository.purgeOlderThan(
    Preferences.instance.getInt(Preferences.tripRetentionDays) ??
        Preferences.defaultTripRetentionDays,
  ));
  // Push any trips that didn't reach the backend on stop (offline at the
  // time, server 5xx, etc.). Idempotent server-side keyed on trip UUID.
  unawaited(TripSync.pushPending());
  // Re-confirm Traccar device registration on every cold start. Auto Backup
  // restores `Preferences.id`, but the matching device record may have been
  // wiped server-side (admin cleanup, account-renaming, etc.). Without this
  // OsmAndSender hits HTTP 400 on every position post and trips don't show
  // up in the Traccar UI.
  unawaited(_ensureTraccarDevice());
  // Periodic flush of GPS waypoints buffered for active trips (parallel
  // sink to Traccar; powers the Web Admin's polyline render).
  PositionSender.start();
  isAuthenticated.value = TraccarApi.isLoggedIn || BackendApi.isPaired;
  needsOnboarding.value =
      !(Preferences.instance.getBool(Preferences.onboardingDone) ?? false);
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  Future<void> _initLinks() async {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null) {
      final paired = await ConfigurationService.applyUri(uri);
      if (paired) {
        isAuthenticated.value = true;
        await _promptSetPassword();
      }
    }
    appLinks.uriLinkStream.listen((uri) async {
      final paired = await ConfigurationService.applyUri(uri);
      if (paired) {
        isAuthenticated.value = true;
        await _promptSetPassword();
      }
    });
  }

  Future<void> _promptSetPassword() async {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return;
    await navigatorKey.currentState!.push<bool>(
      MaterialPageRoute(builder: (_) => const SetPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) => MaterialApp(
        scaffoldMessengerKey: messengerKey,
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          ),
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: isAuthenticated,
          builder: (context, loggedIn, _) {
            if (!loggedIn) {
              return LoginScreen(
                onLoggedIn: () => isAuthenticated.value = true,
              );
            }
            return ValueListenableBuilder<bool>(
              valueListenable: needsOnboarding,
              builder: (context, needs, _) {
                if (needs) {
                  return OnboardingScreen(
                    onFinished: () => needsOnboarding.value = false,
                  );
                }
                return Stack(
                  children: const [
                    QuickActionsInitializer(),
                    MainScreen(),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
