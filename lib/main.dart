import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:autologic_drive/geolocation_service.dart';
import 'package:autologic_drive/password_service.dart';
import 'package:autologic_drive/quick_actions.dart';
import 'package:autologic_drive/trip/bluetooth_watcher.dart';
import 'package:autologic_drive/trip/trip_controller.dart';
import 'package:autologic_drive/util/notifications.dart';

import 'auth/traccar_api.dart';
import 'l10n/app_localizations.dart';
import 'main_screen.dart';
import 'preferences.dart';
import 'configuration_service.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();
  appLocale.value = Locale(
    Preferences.instance.getString(Preferences.language) ?? 'sk',
  );
  AppNotifications.navigatorKey = navigatorKey;
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
  isAuthenticated.value = TraccarApi.isLoggedIn;
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
      await ConfigurationService.applyUri(uri);
    }
    appLinks.uriLinkStream.listen((uri) async {
      await ConfigurationService.applyUri(uri);
    });
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
