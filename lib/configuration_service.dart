import 'preferences.dart';
import 'tracking/engine.dart';
import 'util/app_logger.dart';

class ConfigurationService {
  /// Applies deep-link / QR-code configuration. Supported query parameters:
  ///
  /// - `api` — Traccar REST endpoint (e.g. `https://server.com`)
  /// - `osmand` (or legacy `url`) — OsmAnd ingest endpoint (e.g. `http://server.com:5055`)
  /// - `email` — pre-fill the login screen email field
  /// - per-vehicle / tracking tunables already supported by upstream
  ///
  /// Examples:
  /// - `autologic-drive://configure?api=https%3A%2F%2Fexample.com&email=jano%40firma.sk`
  /// - `https://example.com/?osmand=http%3A%2F%2Fexample.com%3A5055&email=jano%40firma.sk`
  static Future<void> applyUri(Uri uri) async {
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
      'osmand=${osmandUrl != null}, email=${email != null})',
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
