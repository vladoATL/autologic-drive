/// Login screen — entry point when the user is not authenticated.
///
/// Submits credentials to Traccar's `/api/session` and, on success,
/// auto-registers the phone as a device under the logged-in user
/// (uniqueId = the random `Preferences.id` we already generated).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../auth/traccar_api.dart';
import '../configuration_service.dart';
import '../l10n/app_localizations.dart';
import '../preferences.dart';
import '../util/app_logger.dart';
import 'qr_scan_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController(
    text: Preferences.instance.getString(Preferences.authEmail) ?? '',
  );
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.loginEmptyFields);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TraccarApi.login(email, password);
      await _registerDevice();
      if (!mounted) return;
      widget.onLoggedIn();
    } on TraccarApiException catch (e) {
      setState(() => _error =
          e.statusCode == 401 || e.statusCode == 400
              ? AppLocalizations.of(context)!.loginBadCredentials
              : e.message);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerDevice() async {
    final uniqueId = Preferences.instance.getString(Preferences.id);
    if (uniqueId == null) return;
    final name = 'Drive · ${Platform.operatingSystem}';
    try {
      await TraccarApi.ensureDevice(name: name, uniqueId: uniqueId);
    } catch (error) {
      // Don't block login if device registration fails — driver can still
      // see the trip card; positions just won't be accepted by the server
      // until the device is registered manually. Log it loudly.
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
    await ConfigurationService.applyUri(uri);
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.directions_car, size: 64),
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
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _busy ? null : _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(loc.loginButton),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
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
    );
  }
}
