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
      Preferences.instance.getString(Preferences.backendApiUrl) ?? '';

  static String? get _accessToken {
    final t = Preferences.instance.getString(Preferences.backendAccessToken);
    return (t == null || t.isEmpty) ? null : t;
  }

  /// True iff a backend access token is currently stored. Does not validate
  /// the token's signature or expiry — call [me] for an authoritative check.
  static bool get isPaired => _accessToken != null;

  /// Set to `true` once a refresh attempt fails — stops the per-30s flush
  /// loop from spamming hopeless 401s into the log. Cleared on successful
  /// pair / login / refresh.
  static bool _sessionDead = false;

  /// True iff a previous refresh attempt failed and we shouldn't keep
  /// hammering the backend until the user logs in again.
  static bool get isSessionDead => _sessionDead;

  /// Return an access token guaranteed not to be expired (within a 30 s
  /// safety margin). Triggers a [refresh] if the stored token is past
  /// `backendAccessExpiresAt`. Returns null when there is no refresh token,
  /// when refresh fails, or when the session has been marked dead.
  ///
  /// Callers (PositionSender, TripSync, …) should treat null as "skip this
  /// HTTP call quietly" — do NOT log noisy errors on every flush tick.
  static Future<String?> getValidAccessToken() async {
    if (_sessionDead) return null;
    final current = _accessToken;
    if (current == null) return null;
    final expiresStr =
        Preferences.instance.getString(Preferences.backendAccessExpiresAt);
    if (expiresStr != null && expiresStr.isNotEmpty) {
      final exp = DateTime.tryParse(expiresStr);
      if (exp != null &&
          exp.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        return current;
      }
    }
    final pair = await refresh();
    if (pair == null) {
      AppLogger.warn('Backend session dead — refresh failed, will not retry until next login');
      _sessionDead = true;
      return null;
    }
    return pair.accessToken;
  }

  /// One-shot retry on 401: ask the backend for a fresh token and rebuild
  /// the headers. Returns null if the refresh failed (caller should give up
  /// quietly). Use this from the body of any 401 branch, e.g.:
  /// ```
  /// if (resp.statusCode == 401) {
  ///   final fresh = await BackendApi.refreshAfterUnauthorized();
  ///   if (fresh == null) return giveUp;
  ///   resp = await http.post(url, headers: { 'Authorization': 'Bearer $fresh' }, ...);
  /// }
  /// ```
  static Future<String?> refreshAfterUnauthorized() async {
    if (_sessionDead) return null;
    final pair = await refresh();
    if (pair == null) {
      AppLogger.warn('Backend session dead after 401 — refresh failed');
      _sessionDead = true;
      return null;
    }
    return pair.accessToken;
  }

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
    _sessionDead = false;
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
    _sessionDead = false;
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
    _sessionDead = false;
    return pair;
  }

  /// Set a password for the currently paired driver so they can log in to
  /// the Web Admin later. Requires an authenticated session.
  static Future<void> setPassword(String newPassword) async {
    final token = await getValidAccessToken();
    if (token == null) {
      throw const BackendApiException('Not authenticated', 401);
    }
    final url = Uri.parse('$_baseUrl/api/v1/auth/set-password');
    final resp = await http.post(
      url,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer $token',
      },
      body: jsonEncode({'newPassword': newPassword}),
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw BackendApiException(
        resp.body.isNotEmpty ? resp.body : 'set-password failed',
        resp.statusCode,
      );
    }
    AppLogger.info('Backend set-password OK');
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
