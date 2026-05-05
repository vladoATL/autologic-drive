/// Compact card on the home screen showing the live status of every
/// permission Drive needs to record a trip cleanly. Tap a denied row to
/// open the OS settings page and grant it.
///
/// Re-evaluated on every app resume so the card reflects whatever the
/// driver toggled in Android Settings while the app was backgrounded.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../trip/trip_state.dart';
import '../../util/app_logger.dart';

class _PermItem {
  final String Function(AppLocalizations) labelOf;
  final Permission permission;
  const _PermItem(this.labelOf, this.permission);
}

const _items = <_PermItem>[
  _PermItem(_locWhenInUse, Permission.locationWhenInUse),
  _PermItem(_locAlways, Permission.locationAlways),
  _PermItem(_activityRec, Permission.activityRecognition),
  _PermItem(_btConnect, Permission.bluetoothConnect),
  _PermItem(_notifications, Permission.notification),
];

String _locWhenInUse(AppLocalizations l) => l.permLocationWhenInUse;
String _locAlways(AppLocalizations l) => l.permLocationAlways;
String _activityRec(AppLocalizations l) => l.permActivityRecognition;
String _btConnect(AppLocalizations l) => l.permBluetoothConnect;
String _notifications(AppLocalizations l) => l.permNotifications;

class PermissionStatusCard extends StatefulWidget {
  const PermissionStatusCard({super.key});

  @override
  State<PermissionStatusCard> createState() => _PermissionStatusCardState();
}

class _PermissionStatusCardState extends State<PermissionStatusCard>
    with WidgetsBindingObserver {
  Map<Permission, PermissionStatus> _statuses = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppLogger.info('PermissionStatusCard.initState');
    WidgetsBinding.instance.addObserver(this);
    // Re-evaluate when a trip starts/stops too — Tracelet sometimes
    // surfaces a previously-hidden permission denial only after it tries
    // to spin up its location service.
    tripState.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    tripState.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    AppLogger.info('PermissionStatusCard._refresh() start');
    try {
      final results = await Future.wait(
        _items.map((i) async => MapEntry(i.permission, await i.permission.status)),
      );
      if (!mounted) {
        AppLogger.warn('PermissionStatusCard._refresh() — not mounted, skipping setState');
        return;
      }
      final map = Map<Permission, PermissionStatus>.fromEntries(results);
      AppLogger.info(
        'Permissions refresh: ${map.entries.map((e) => "${e.key.toString().split('.').last}=${e.value.toString().split('.').last}").join(", ")}',
      );
      setState(() {
        _statuses = map;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('PermissionStatusCard._refresh() threw: $e\n$st');
    }
  }

  Future<void> _onTap(_PermItem item, PermissionStatus status) async {
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await item.permission.request();
    }
    await _refresh();
  }

  bool get _allGreen => _statuses.values.every((s) => s.isGranted);

  @override
  Widget build(BuildContext context) {
    // Hide entirely while loading or when every permission is granted —
    // the home screen shouldn't be cluttered with a "all good" card.
    // The card is purely an attention-getter for problems.
    if (_loading || _allGreen) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.permSomeMissing,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh),
                  tooltip: loc.permRefresh,
                  onPressed: _refresh,
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final item in _items)
              if (!(_statuses[item.permission]?.isGranted ?? false))
                _row(item,
                    _statuses[item.permission] ?? PermissionStatus.denied,
                    theme, loc),
          ],
        ),
      ),
    );
  }

  Widget _row(_PermItem item, PermissionStatus status, ThemeData theme,
      AppLocalizations loc) {
    final granted = status.isGranted;
    final color = granted
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return InkWell(
      onTap: granted ? null : () => _onTap(item, status),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              granted ? Icons.check_circle : Icons.cancel_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.labelOf(loc),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!granted)
              Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
