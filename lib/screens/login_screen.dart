/// Login screen — entry point when the user is not authenticated.
///
/// Submits credentials to Traccar's `/api/session` and, on success,
/// auto-registers the phone as a device under the logged-in user
/// (uniqueId = the random `Preferences.id` we already generated).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../auth/backend_api.dart';
import '../auth/biometric_login.dart';
import '../auth/traccar_api.dart';
import '../configuration_service.dart';
import '../l10n/app_localizations.dart';
import '../preferences.dart';
import '../trip/bluetooth_helper.dart';
import '../trip/vehicle_repository.dart';
import '../util/app_logger.dart';
import 'qr_scan_screen.dart';
import 'set_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // TODO(0.9.x): remove dev-prefill before release.
  final _emailCtrl = TextEditingController(
    text: Preferences.instance.getString(Preferences.authEmail) ?? 'vlado@starlogic.net',
  );
  // TODO(0.9.x): remove dev-prefill before release.
  final _passwordCtrl = TextEditingController(text: 'Slovensko12');
  bool _busy = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final canAuth = await BiometricLogin.canAuthenticate;
    final hasSaved = await BiometricLogin.hasSavedCredentials;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = canAuth;
      _hasSavedCredentials = hasSaved;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login({String? overrideEmail, String? overridePassword}) async {
    final email = (overrideEmail ?? _emailCtrl.text).trim();
    final password = overridePassword ?? _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.loginEmptyFields);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Try the AutoLogic Backend first — that's where SetPasswordScreen
      // writes the password and where the canonical user record lives.
      // Fall back to legacy Traccar login if backend rejects (e.g. user
      // never set a backend password, only paired via QR + Traccar email).
      var backendOk = false;
      try {
        await BackendApi.login(email, password);
        backendOk = true;
        AppLogger.info('Login: backend login OK, will try Traccar in parallel');
      } on BackendApiException catch (e) {
        AppLogger.info('Login: backend rejected ($e), falling back to Traccar');
      }

      // Try Traccar so OsmAndSender can write positions and the Vehicles
      // screen can rename the device. Failure here is OK if backend
      // succeeded — Traccar password may be stale post-`set-password`,
      // but the device's uniqueId still works on the OsmAnd ingest port
      // without auth.
      try {
        await TraccarApi.login(email, password);
        AppLogger.info('Login: Traccar login OK');
      } on TraccarApiException catch (e) {
        if (!backendOk) {
          // Both failed — surface the Traccar error verbatim.
          setState(() => _error = e.statusCode == 401 || e.statusCode == 400
              ? AppLocalizations.of(context)!.loginBadCredentials
              : e.message);
          return;
        }
        AppLogger.warn('Login: Traccar rejected after backend OK ($e) — continuing without Traccar cookie');
      }

      if (_rememberMe) {
        await BiometricLogin.save(email: email, password: password);
      } else {
        await BiometricLogin.clear();
      }
      await _registerDevice();
      if (!mounted) return;
      widget.onLoggedIn();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometricLogin() async {
    setState(() => _busy = true);
    try {
      final loc = AppLocalizations.of(context)!;
      final creds = await BiometricLogin.unlock(loc.biometricReason);
      if (creds == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      _emailCtrl.text = creds.email;
      _passwordCtrl.text = creds.password;
      await _login(overrideEmail: creds.email, overridePassword: creds.password);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _registerDevice() async {
    final uniqueId = Preferences.instance.getString(Preferences.id);
    if (uniqueId == null) return;
    // First-login default — prefer the phone's BT adapter / device name
    // ("Galaxy S24 Ultra") over the generic "Drive · android" placeholder.
    // Superseded by the primary vehicle label as soon as the driver pairs
    // a vehicle (VehicleRepository.upsert pushes that name to Traccar) or
    // by an admin rename on the server (pulled below).
    final detected = await BluetoothHelper.deviceLabel();
    final name = (detected != null && detected.isNotEmpty)
        ? detected
        : 'Drive · ${Platform.operatingSystem}';
    AppLogger.info('Device registration name resolved to "$name" (detected="${detected ?? "null"}")');
    try {
      await TraccarApi.ensureDevice(name: name, uniqueId: uniqueId);
      // If the driver already paired a vehicle in a previous session, push
      // its label now; if the admin pre-named the device server-side, mirror
      // that into the local primary vehicle.
      await VehicleRepository.pullDeviceNameFromServer();
    } catch (error) {
      AppLogger.error('Device auto-registration failed: $error');
    }
  }

  void _showRegisterPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.loginRegisterComingSoon),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    Uri? uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      uri = null;
    }
    if (uri == null) {
      setState(() => _error = AppLocalizations.of(context)!.qrInvalid);
      return;
    }
    final paired = await ConfigurationService.applyUri(uri);
    if (paired) {
      // Backend pair succeeded — driver is authenticated. Offer to set a
      // password for later web-admin login (skippable).
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const SetPasswordScreen()),
      );
      if (!mounted) return;
      widget.onLoggedIn();
      return;
    }
    final email = Preferences.instance.getString(Preferences.authEmail);
    if (email != null) _emailCtrl.text = email;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.qrApplied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final apiUrl = Preferences.instance.getString(Preferences.apiUrl) ?? '';
    final showBiometric = _biometricAvailable && _hasSavedCredentials;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              Theme.of(context).colorScheme.onSurface,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              'assets/icon/autologic_icon.png',
                              width: 96,
                              height: 96,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'AutoLogic Drive',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: _emailCtrl,
                          decoration: InputDecoration(
                            labelText: loc.loginEmailLabel,
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordCtrl,
                          decoration: InputDecoration(
                            labelText: loc.loginPasswordLabel,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              tooltip: _obscurePassword
                                  ? loc.passwordShow
                                  : loc.passwordHide,
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          obscureText: _obscurePassword,
                          enabled: !_busy,
                          onSubmitted: (_) => _busy ? null : _login(),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(loc.rememberMeLabel),
                          value: _rememberMe,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _rememberMe = v ?? true),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy ? null : _login,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(loc.loginButton),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        if (showBiometric) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _biometricLogin,
                            icon: const Icon(Icons.fingerprint),
                            label: Text(loc.biometricLoginButton),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _scanQr,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(loc.qrScanButton),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _showRegisterPlaceholder,
                          child: Text(loc.loginRegisterButton),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${loc.urlLabel}: $apiUrl',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
