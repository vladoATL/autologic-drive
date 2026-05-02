/// "Remember me" + biometric / device-credential unlock for the login flow.
///
/// When the driver checks "Zapamätať prihlásenie" we store the email +
/// password in `flutter_secure_storage` (Android Keystore-backed). On the
/// next launch the login screen offers a biometric / PIN prompt; on success
/// we replay the saved credentials through `TraccarApi.login` so the driver
/// doesn't have to type anything.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricLogin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kEmail = 'remember_email';
  static const _kPassword = 'remember_password';

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> get canAuthenticate async {
    try {
      final supported = await _auth.isDeviceSupported();
      return supported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get hasSavedCredentials async {
    final email = await _storage.read(key: _kEmail);
    final password = await _storage.read(key: _kPassword);
    return email != null &&
        email.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
  }

  static Future<void> save({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kPassword);
  }

  static Future<({String email, String password})?> unlock(
    String reason,
  ) async {
    final ok = await _auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false, // allow PIN / pattern fallback
        stickyAuth: true,
      ),
    );
    if (!ok) return null;
    final email = await _storage.read(key: _kEmail);
    final password = await _storage.read(key: _kPassword);
    if (email == null || password == null) return null;
    return (email: email, password: password);
  }
}
