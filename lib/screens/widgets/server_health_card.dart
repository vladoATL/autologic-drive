/// Live reachability check for the three back-end services Drive depends
/// on — Traccar OsmAnd ingest (port 5055), Traccar admin (8082) and the
/// AutoLogic Backend (8080). Useful when the driver suspects the server
/// is down or the URLs in `Preferences` are misconfigured (e.g. an old
/// `localhost:8080` left over from a dev build).
///
/// Pings each endpoint in parallel with a 5 s HTTP timeout. Status is
/// stale by design: tap *Skontrolovať* to refresh.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../preferences.dart';

class ServerHealthCard extends StatefulWidget {
  const ServerHealthCard({super.key});

  @override
  State<ServerHealthCard> createState() => _ServerHealthCardState();
}

class _Endpoint {
  final String label;
  final String url;
  /// Status codes that count as "alive". Some endpoints respond with
  /// 4xx to a bare GET (no auth, no params) — that still proves the
  /// service is up and reachable.
  final Set<int> aliveCodes;
  const _Endpoint(this.label, this.url, this.aliveCodes);
}

class _Result {
  final bool alive;
  final int? code;
  final String? error;
  const _Result({required this.alive, this.code, this.error});
}

class _ServerHealthCardState extends State<ServerHealthCard> {
  static const _timeout = Duration(seconds: 5);

  Map<String, _Result> _results = const {};
  bool _checking = false;

  List<_Endpoint> _endpoints() {
    final p = Preferences.instance;
    return [
      _Endpoint(
        'Traccar OsmAnd',
        p.getString(Preferences.url) ?? '',
        // Traccar OsmAnd 400s any GET without lat/lon params — that's
        // proof of life, not an error.
        const {200, 400},
      ),
      _Endpoint(
        'Traccar admin',
        p.getString(Preferences.apiUrl) ?? '',
        const {200, 401, 404},
      ),
      _Endpoint(
        'AutoLogic Backend',
        // Hit a known endpoint instead of root — `/api/v1/auth/me` returns
        // 401 without a token, which is unambiguous proof the .NET backend
        // is up. Root path 404 is also accepted as a fallback.
        '${p.getString(Preferences.backendApiUrl) ?? ''}/api/v1/auth/me',
        const {200, 401, 404},
      ),
    ];
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final endpoints = _endpoints();
    final futures = endpoints.map((e) => _ping(e));
    final results = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _results = {
        for (var i = 0; i < endpoints.length; i++)
          endpoints[i].label: results[i],
      };
      _checking = false;
    });
  }

  Future<_Result> _ping(_Endpoint e) async {
    if (e.url.isEmpty) {
      return const _Result(alive: false, error: 'URL not set');
    }
    try {
      final resp = await http.get(Uri.parse(e.url)).timeout(_timeout);
      return _Result(
        alive: e.aliveCodes.contains(resp.statusCode),
        code: resp.statusCode,
      );
    } catch (err) {
      return _Result(alive: false, error: err.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final endpoints = _endpoints();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.serverHealthTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_checking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh),
                    tooltip: loc.serverHealthRefresh,
                    onPressed: _check,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final e in endpoints)
              _row(e, _results[e.label], theme),
          ],
        ),
      ),
    );
  }

  Widget _row(_Endpoint e, _Result? result, ThemeData theme) {
    final IconData icon;
    final Color color;
    final String trailing;
    if (result == null) {
      icon = Icons.help_outline;
      color = theme.colorScheme.outline;
      trailing = '…';
    } else if (result.alive) {
      icon = Icons.check_circle;
      color = theme.colorScheme.primary;
      trailing = result.code?.toString() ?? 'OK';
    } else {
      icon = Icons.cancel_outlined;
      color = theme.colorScheme.error;
      trailing = result.code?.toString() ??
          (result.error?.split(':').first ?? 'FAIL');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: theme.textTheme.bodyMedium),
                Text(
                  e.url.isEmpty ? '(URL not set)' : e.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
