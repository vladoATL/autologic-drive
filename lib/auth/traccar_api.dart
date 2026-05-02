/// Thin Traccar REST client.
///
/// Authenticates via `POST /api/session` (form-urlencoded `email` +
/// `password`), captures the `JSESSIONID` cookie from `Set-Cookie`, and
/// sends it back on every subsequent request. Cookie + user metadata
/// persist in `Preferences` so the user stays logged in across app
/// restarts.
///
/// We only call the endpoints the app currently needs:
/// - `/api/session` (POST/GET/DELETE)
/// - `/api/devices` (GET to look up by uniqueId, POST to create).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../preferences.dart';
import '../util/app_logger.dart';

class TraccarApiException implements Exception {
  final int? statusCode;
  final String message;
  const TraccarApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'TraccarApi[$statusCode]: $message';
}

class TraccarApi {
  static String get _baseUrl =>
      Preferences.instance.getString(Preferences.apiUrl) ?? '';

  static String? get cookie {
    final c = Preferences.instance.getString(Preferences.authCookie);
    return (c == null || c.isEmpty) ? null : c;
  }

  static bool get isLoggedIn => cookie != null;

  static Map<String, String> _headers({String? contentType}) {
    final h = <String, String>{};
    if (cookie != null) h[HttpHeaders.cookieHeader] = cookie!;
    if (contentType != null) h[HttpHeaders.contentTypeHeader] = contentType;
    return h;
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final url = Uri.parse('$_baseUrl/api/session');
    final resp = await http.post(
      url,
      headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
      body: {'email': email, 'password': password},
    );
    if (resp.statusCode != 200) {
      AppLogger.warn('Login failed: HTTP ${resp.statusCode} ${resp.body}');
      throw TraccarApiException(
        resp.body.isNotEmpty ? resp.body : 'Login failed',
        resp.statusCode,
      );
    }
    final rawCookie = resp.headers['set-cookie'];
    if (rawCookie != null) {
      // Keep only the JSESSIONID name=value pair; strip Path/HttpOnly etc.
      final firstAttr = rawCookie.split(';').first.trim();
      await Preferences.instance.setString(Preferences.authCookie, firstAttr);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    await Preferences.instance.setString(Preferences.authEmail, email);
    await Preferences.instance.setInt(
      Preferences.authUserId,
      (body['id'] as num).toInt(),
    );
    final name = (body['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      await Preferences.instance.setString(Preferences.driverName, name);
    }
    AppLogger.info('Login OK: $email');
    return body;
  }

  static Future<bool> verifySession() async {
    if (!isLoggedIn) return false;
    final url = Uri.parse('$_baseUrl/api/session');
    try {
      final resp = await http.get(url, headers: _headers());
      return resp.statusCode == 200;
    } catch (error) {
      AppLogger.warn('Session verify failed: $error');
      return false;
    }
  }

  static Future<void> logout() async {
    final url = Uri.parse('$_baseUrl/api/session');
    try {
      await http.delete(url, headers: _headers());
    } catch (error) {
      AppLogger.warn('Logout request failed: $error');
    }
    await Preferences.instance.setString(Preferences.authCookie, '');
    await Preferences.instance.setString(Preferences.authEmail, '');
    AppLogger.info('Logout');
  }

  static Future<List<dynamic>> listMyDevices({String? uniqueId}) async {
    final query = uniqueId != null ? '?uniqueId=$uniqueId' : '';
    final url = Uri.parse('$_baseUrl/api/devices$query');
    final resp = await http.get(url, headers: _headers());
    if (resp.statusCode != 200) {
      throw TraccarApiException('listDevices failed', resp.statusCode);
    }
    return jsonDecode(resp.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createDevice({
    required String name,
    required String uniqueId,
  }) async {
    final url = Uri.parse('$_baseUrl/api/devices');
    final resp = await http.post(
      url,
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'name': name, 'uniqueId': uniqueId}),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw TraccarApiException(
        resp.body.isNotEmpty ? resp.body : 'createDevice failed',
        resp.statusCode,
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Look the device up by `uniqueId`; if missing, create it. Returns the
  /// device JSON map. Idempotent — safe to call after every login.
  static Future<Map<String, dynamic>> ensureDevice({
    required String name,
    required String uniqueId,
  }) async {
    try {
      final existing = await listMyDevices(uniqueId: uniqueId);
      if (existing.isNotEmpty) {
        AppLogger.info('Device $uniqueId already registered');
        return (existing.first as Map).cast<String, dynamic>();
      }
    } catch (error) {
      AppLogger.warn('listDevices lookup failed (continuing to create): $error');
    }
    AppLogger.info('Creating device $uniqueId ($name)');
    return await createDevice(name: name, uniqueId: uniqueId);
  }

  /// Read the current Traccar-side name of the device with `uniqueId`.
  /// Returns `null` if not found / not logged in.
  static Future<String?> fetchDeviceName(String uniqueId) async {
    if (!isLoggedIn) return null;
    try {
      final list = await listMyDevices(uniqueId: uniqueId);
      if (list.isEmpty) return null;
      final device = (list.first as Map).cast<String, dynamic>();
      return device['name'] as String?;
    } catch (error) {
      AppLogger.warn('fetchDeviceName error: $error');
      return null;
    }
  }

  /// Rename an already-registered device by `uniqueId`. No-op if the device
  /// isn't found or the name already matches.
  static Future<void> renameDevice({
    required String uniqueId,
    required String newName,
  }) async {
    if (!isLoggedIn) return;
    try {
      final list = await listMyDevices(uniqueId: uniqueId);
      if (list.isEmpty) {
        AppLogger.warn('renameDevice: device $uniqueId not found');
        return;
      }
      final device = (list.first as Map).cast<String, dynamic>();
      if (device['name'] == newName) return;
      device['name'] = newName;
      final id = device['id'];
      final url = Uri.parse('$_baseUrl/api/devices/$id');
      final resp = await http.put(
        url,
        headers: _headers(contentType: 'application/json'),
        body: jsonEncode(device),
      );
      if (resp.statusCode != 200) {
        AppLogger.warn(
          'renameDevice failed: HTTP ${resp.statusCode} ${resp.body}',
        );
        return;
      }
      AppLogger.info('Device $uniqueId renamed to "$newName"');
    } catch (error) {
      AppLogger.warn('renameDevice error: $error');
    }
  }
}
