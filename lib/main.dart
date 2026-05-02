import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:autologic_drive/geolocation_service.dart';
import 'package:autologic_drive/password_service.dart';
import 'package:autologic_drive/quick_actions.dart';

import 'l10n/app_localizations.dart';
import 'main_screen.dart';
import 'preferences.dart';
import 'configuration_service.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

const _seedColor = Color(0xFF1A1A1A);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();
  await PasswordService.migrate();
  await GeolocationService.init();
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
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
      home: Stack(
        children: const [
          QuickActionsInitializer(),
          MainScreen(),
        ],
      ),
    );
  }
}
