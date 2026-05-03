import 'auth/backend_api.dart';
import 'preferences.dart';
import 'tracking/engine.dart';
import 'util/app_logger.dart';

class ConfigurationService {
  /// Applies deep-link / QR-code configuration. Supported query parameters:
  ///
  /// - `api` — Traccar REST / AutoLogic Backend endpoint (e.g. `https://server.com`)
  /// - `osmand` (or legacy `url`) — OsmAnd ingest endpoint (e.g. `http://server.com:5055`)
  /// - `email` — pre-fill the login screen email field
  /// - `token` — one-time pairing token issued by the backend's
  ///   `POST /api/v1/onboarding/invite` endpoint. If present, this method
  ///   exchanges it for a backend access + refresh token via
  ///   `POST /api/v1/auth/pair` and fetches the driver's identity via
  ///   `GET /api/v1/auth/me`. After a successful pair the driver is
  ///   considered authenticated (no Traccar `/api/session` call needed).
  /// - per-vehicle / tracking tunables already supported by upstream
  ///
  /// Examples:
  /// - `autologic-drive://configure?api=https%3A%2F%2Fexample.com&email=jano%40firma.sk`
  /// - `autologic-drive://configure?api=https%3A%2F%2Fexample.com&token=AbC...&email=jano%40firma.sk`
  /// - `https://example.com/?osmand=http%3A%2F%2Fexample.com%3A5055&email=jano%40firma.sk`
  ///
  /// Returns `true` if the deep link triggered a successful backend pair
  /// (i.e. the user is now authenticated). Returns `false` for config-only
  /// links or when the pair attempt fails.
  static Future<bool> applyUri(Uri uri) async {
    final params = uri.queryParameters;

    // OsmAnd ingest URL — legacy `url` param OR new `osmand` param OR derived
    // from the http(s) scheme of the link itself.
    final osmandUrl = params['osmand'] ?? params['url'];
    if (osmandUrl != null && osmandUrl.isNotEmpty) {
      await Preferences.instance.setString(Preferences.url, osmandUrl);
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      await Preferences.instance.setString(Preferences.url, '${uri.origin}${uri.path}');
    }

    // Traccar REST API URL.
    final apiUrl = params['api'];
    if (apiUrl != null && apiUrl.isNotEmpty) {
      await Preferences.instance.setString(Preferences.apiUrl, apiUrl);
    }

    // Pre-fill login email.
    final email = params['email'];
    if (email != null && email.isNotEmpty) {
      await Preferences.instance.setString(Preferences.authEmail, email);
    }

    AppLogger.info(
      'Applied deep-link config (api=${apiUrl != null}, '
      'osmand=${osmandUrl != null}, email=${email != null}, '
      'token=${(params['token']?.isNotEmpty ?? false)})',
    );

    await _applyStringParameter(params, Preferences.id);
    await _applyStringParameter(params, Preferences.accuracy);
    await _applyIntParameter(params, Preferences.distance);
    await _applyIntParameter(params, Preferences.interval);
    await _applyIntParameter(params, Preferences.angle);
    await _applyIntParameter(params, Preferences.heartbeat);
    await _applyIntParameter(params, Preferences.fastestInterval);
    await _applyBoolParameter(params, Preferences.buffer);
    await _applyBoolParameter(params, Preferences.wakelock);
    await _applyBoolParameter(params, Preferences.stopDetection);
    await engine.setConfig(Preferences.trackingConfig(true));

    // Backend pairing — if the QR carries a one-time token, exchange it for
    // a JWT pair and fetch identity. Failure here is non-fatal: the user
    // can still log in manually with email + password.
    final token = params['token'];
    if (token != null && token.isNotEmpty) {
      try {
        await BackendApi.pair(token);
        await BackendApi.me();
        AppLogger.info('Backend pair via deep-link OK');
        return true;
      } catch (error) {
        AppLogger.warn('Backend pair failed, falling back to manual login: $error');
      }
    }
    return false;
  }

  static Future<void> _applyStringParameter(
      Map<String, String> parameters, String key) async {
    final value = parameters[key];
    if (value != null) {
      await Preferences.instance.setString(key, value);
    }
  }

  static Future<void> _applyIntParameter(
      Map<String, String> parameters, String key) async {
    final stringValue = parameters[key];
    if (stringValue != null) {
      final value = int.tryParse(stringValue);
      if (value != null) {
        await Preferences.instance.setInt(key, value);
      }
    }
  }

  static Future<void> _applyBoolParameter(
      Map<String, String> parameters, String key) async {
    final value = parameters[key];
    if (value != null) {
      switch (value) {
        case 'false':
          await Preferences.instance.setBool(key, false);
        case 'true':
          await Preferences.instance.setBool(key, true);
      }
    }
  }
}
