/// AutoLogic Backend (.NET 10) REST client.
///
/// Talks to the multi-tenant backend that sits in front of Traccar
/// (deployed under the same `${GPS_DOMAIN}` as `/api/v1/*`). Used to:
///
/// 1. **Pair** a driver via QR onboarding token (`POST /api/v1/auth/pair`).
/// 2. **Login** via email + password (`POST /api/v1/auth/login`) — alternative
///    to the legacy Traccar `/api/session` flow.
/// 3. **Fetch identity** of the current user (`GET /api/v1/auth/me`).
/// 4. **Refresh** the access token (`POST /api/v1/auth/refresh`).
/// 5. **Logout** — revoke the current refresh token.
///
/// Tokens persist in [Preferences] (`backend_access_token`, `backend_refresh_token`,
/// `backend_access_expires_at`) so the user stays paired across app restarts.
/// All long-lived state can be cleared via [clearSession].
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../preferences.dart';
import '../util/app_logger.dart';

class BackendApiException implements Exception {
  final int? statusCode;
  final String message;
  const BackendApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'BackendApi[$statusCode]: $message';
}

class BackendApi {
  static String get _baseUrl =>
      Preferences.instance.getString(Preferences.apiUrl) ?? '';

  static String? get _accessToken {
    final t = Preferences.instance.getString(Preferences.backendAccessToken);
    return (t == null || t.isEmpty) ? null : t;
  }

  /// True iff a backend access token is currently stored. Does not validate
  /// the token's signature or expiry — call [me] for an authoritative check.
  static bool get isPaired => _accessToken != null;

  static Map<String, String> _headers({bool authed = false, String? contentType}) {
    final h = <String, String>{};
    if (contentType != null) h[HttpHeaders.contentTypeHeader] = contentType;
    if (authed && _accessToken != null) {
      h[HttpHeaders.authorizationHeader] = 'Bearer ${_accessToken!}';
    }
    return h;
  }

  /// Exchange a one-time pairing token (32 bytes, base64url) for an access +
  /// refresh token pair. Tokens are persisted on success.
  static Future<TokenPair> pair(String pairingToken) async {
    final url = Uri.parse('$_baseUrl/api/v1/auth/pair');
    final resp = await http.post(
      url,
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'token': pairingToken}),
    );
    if (resp.statusCode != 200) {
      AppLogger.warn('Pair failed: HTTP ${resp.statusCode} ${resp.body}');
      throw BackendApiException(
        resp.body.isNotEmpty ? resp.body : 'Pair failed',
        resp.statusCode,
      );
    }
    final pair = TokenPair.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    await pair.save();
    AppLogger.info('Backend pair OK');
    return pair;
  }

  /// Email + password login. Persists the resulting token pair.
  static Future<TokenPair> login(String email, String password) async {
    final url = Uri.parse('$_baseUrl/api/v1/auth/login');
    final resp = await http.post(
      url,
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (resp.statusCode != 200) {
      throw BackendApiException(
        resp.body.isNotEmpty ? resp.body : 'Login failed',
        resp.statusCode,
      );
    }
    final pair = TokenPair.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    await pair.save();
    AppLogger.info('Backend login OK: $email');
    return pair;
  }

  /// Fetch the authenticated user identity. Caches the parsed values into
  /// [Preferences] (email, tenantId, role, userId, name).
  static Future<MeResponse> me() async {
    if (!isPaired) {
      throw const BackendApiException('Not paired', 401);
    }
    final url = Uri.parse('$_baseUrl/api/v1/auth/me');
    final resp = await http.get(url, headers: _headers(authed: true));
    if (resp.statusCode != 200) {
      throw BackendApiException(
        resp.body.isNotEmpty ? resp.body : 'me failed',
        resp.statusCode,
      );
    }
    final me = MeResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    await me.cacheToPrefs();
    return me;
  }

  /// Rotate the refresh token. Returns the new pair; old refresh token is
  /// invalidated server-side.
  static Future<TokenPair?> refresh() async {
    final rt = Preferences.instance.getString(Preferences.backendRefreshToken);
    if (rt == null || rt.isEmpty) return null;
    final url = Uri.parse('$_baseUrl/api/v1/auth/refresh');
    final resp = await http.post(
      url,
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'refreshToken': rt}),
    );
    if (resp.statusCode != 200) {
      AppLogger.warn('Refresh failed: HTTP ${resp.statusCode}');
      return null;
    }
    final pair = TokenPair.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    await pair.save();
    return pair;
  }

  /// Best-effort logout: revoke the refresh token server-side and clear
  /// local state. Network failures are swallowed (we still wipe locally).
  static Future<void> logout() async {
    final rt = Preferences.instance.getString(Preferences.backendRefreshToken);
    if (rt != null && rt.isNotEmpty) {
      try {
        final url = Uri.parse('$_baseUrl/api/v1/auth/logout');
        await http.post(
          url,
          headers: _headers(contentType: 'application/json'),
          body: jsonEncode({'refreshToken': rt}),
        );
      } catch (error) {
        AppLogger.warn('Backend logout request failed: $error');
      }
    }
    await clearSession();
    AppLogger.info('Backend logout');
  }

  /// Wipe all backend-side identity (tokens + cached user metadata).
  static Future<void> clearSession() async {
    final p = Preferences.instance;
    await p.setString(Preferences.backendAccessToken, '');
    await p.setString(Preferences.backendRefreshToken, '');
    await p.setString(Preferences.backendAccessExpiresAt, '');
    await p.setString(Preferences.backendUserId, '');
    await p.setString(Preferences.backendTenantId, '');
    await p.setString(Preferences.backendRole, '');
  }
}

class TokenPair {
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  const TokenPair({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['accessToken'] as String,
        accessTokenExpiresAt:
            DateTime.parse(json['accessTokenExpiresAt'] as String),
        refreshToken: json['refreshToken'] as String,
        refreshTokenExpiresAt:
            DateTime.parse(json['refreshTokenExpiresAt'] as String),
      );

  Future<void> save() async {
    final p = Preferences.instance;
    await p.setString(Preferences.backendAccessToken, accessToken);
    await p.setString(Preferences.backendRefreshToken, refreshToken);
    await p.setString(
      Preferences.backendAccessExpiresAt,
      accessTokenExpiresAt.toIso8601String(),
    );
  }
}

class MeResponse {
  final String id;
  final String tenantId;
  final String email;
  final String name;
  final String role;

  const MeResponse({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.name,
    required this.role,
  });

  factory MeResponse.fromJson(Map<String, dynamic> json) => MeResponse(
        id: json['id'] as String,
        tenantId: json['tenantId'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
      );

  Future<void> cacheToPrefs() async {
    final p = Preferences.instance;
    await p.setString(Preferences.backendUserId, id);
    await p.setString(Preferences.backendTenantId, tenantId);
    await p.setString(Preferences.backendRole, role);
    await p.setString(Preferences.authEmail, email);
    if (name.isNotEmpty) {
      await p.setString(Preferences.driverName, name);
    }
  }
}
