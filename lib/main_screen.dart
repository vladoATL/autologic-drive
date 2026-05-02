import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:autologic_drive/main.dart';
import 'package:autologic_drive/password_service.dart';
import 'package:autologic_drive/preferences.dart';
import 'package:autologic_drive/tracking/engine.dart';

import 'l10n/app_localizations.dart';
import 'screens/vehicles_screen.dart';
import 'settings_screen.dart';
import 'status_screen.dart';
import 'trip/bluetooth_watcher.dart';
import 'trip/trip_controller.dart';
import 'trip/trip_state.dart';
import 'trip/vehicle.dart';
import 'trip/vehicle_repository.dart';
import 'util/app_logger.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Backstop the broadcast receiver: ask the OS for currently connected
      // BT devices and replay them as connect events.
      BluetoothWatcher.pollNow();
    }
  }

  Future<void> _checkBatteryOptimizations(BuildContext context) async {
    try {
      if (!await engine.isIgnoringBatteryOptimizations()) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            scrollable: true,
            content: Text(AppLocalizations.of(context)!.optimizationMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  engine.requestIgnoreBatteryOptimizations();
                },
                child: Text(AppLocalizations.of(context)!.okButton),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      debugPrint(error.toString());
    }
  }

  Future<void> _startTrip() async {
    // Auto-start = OFF means "this paired device is not a vehicle, just a
    // BT accessory" (e.g. SmartBox/OBD reader). Hide them from the picker.
    final vehicles =
        VehicleRepository.all().where((v) => v.autoStartTrip).toList();
    Vehicle? chosen;
    if (vehicles.isNotEmpty) {
      chosen = await showDialog<Vehicle>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(AppLocalizations.of(context)!.tripPickVehicle),
          children: [
            for (final v in vehicles)
              SimpleDialogOption(
                child: Text(v.label),
                onPressed: () => Navigator.pop(ctx, v),
              ),
            SimpleDialogOption(
              child: Text(AppLocalizations.of(context)!.tripWithoutVehicle),
              onPressed: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      );
    }

    AppLogger.info('Manual start tap (vehicle=${chosen?.label ?? "none"})');
    try {
      await TripController.start(vehicle: chosen);
      if (mounted) _checkBatteryOptimizations(context);
    } catch (error) {
      if (!mounted) return;
      AppLogger.error('Manual start failed: $error');
      final providerState = await engine.getProviderState();
      if (!mounted) return;
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          duration: const Duration(seconds: 4),
          action: providerState.isPermissionDenied
              ? SnackBarAction(
                  label: AppLocalizations.of(context)!.settingsTitle,
                  onPressed: () => AppSettings.openAppSettings(
                    type: AppSettingsType.settings,
                  ),
                )
              : null,
        ),
      );
    }
  }

  Future<void> _stopTrip() async {
    AppLogger.info('Manual stop tap');
    if (await PasswordService.authenticate(context) && mounted) {
      await TripController.stop();
    }
  }

  Widget _buildAutoDetectCard() {
    final loc = AppLocalizations.of(context)!;
    final autoOn =
        Preferences.instance.getBool(Preferences.autoDetect) ?? false;
    return Card(
      child: SwitchListTile(
        title: Text(loc.autoDetectLabel),
        subtitle: Text(loc.autoDetectHint),
        secondary: const Icon(Icons.bluetooth_searching),
        value: autoOn,
        onChanged: (v) async {
          await Preferences.instance.setBool(Preferences.autoDetect, v);
          AppLogger.info('Auto-detect ${v ? "enabled" : "disabled"}');
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _buildTripCard(TripSnapshot trip) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = trip.active
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  trip.active ? Icons.directions_car : Icons.directions_car_outlined,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trip.active ? loc.tripActive : loc.tripIdle,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            if (trip.active) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const _GpsPulseIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    trip.source == TripTriggerSource.bluetooth
                        ? loc.tripSourceBluetooth
                        : loc.tripSourceManual,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (trip.vehicleLabel != null && trip.vehicleLabel!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_filled, size: 18),
                      const SizedBox(width: 8),
                      Text(trip.vehicleLabel!,
                          style: theme.textTheme.bodyLarge),
                    ],
                  ),
                ),
              if (trip.startedAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _LiveDuration(startedAt: trip.startedAt!),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: trip.active
                  ? FilledButton.icon(
                      onPressed: _stopTrip,
                      icon: const Icon(Icons.stop),
                      label: Text(loc.tripStopButton),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _startTrip,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(loc.tripStartButton),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendDiagnosticLocation() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final p = await engine.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'manual': true},
      );
      await engine.dispatchLocation(p);
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(loc.locationSentToast),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Widget _buildDrawer() {
    final loc = AppLocalizations.of(context)!;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'AutoLogic Drive',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text(loc.vehiclesTitle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VehiclesScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(loc.settingsButton),
              onTap: () async {
                Navigator.pop(context);
                if (await PasswordService.authenticate(context) && mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  setState(() {});
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text(loc.statusButton),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatusScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: Text(loc.locationButton),
              subtitle: Text(
                loc.locationButtonHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.pop(context);
                _sendDiagnosticLocation();
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${loc.idLabel}: ${Preferences.instance.getString(Preferences.id) ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${loc.urlLabel}: ${Preferences.instance.getString(Preferences.url) ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoLogic Drive'),
      ),
      drawer: _buildDrawer(),
      body: ValueListenableBuilder<TripSnapshot>(
        valueListenable: tripState,
        builder: (context, trip, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildTripCard(trip),
              const SizedBox(height: 16),
              _buildAutoDetectCard(),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    AppLocalizations.of(context)!.disclosureMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GpsPulseIndicator extends StatefulWidget {
  const _GpsPulseIndicator();

  @override
  State<_GpsPulseIndicator> createState() => _GpsPulseIndicatorState();
}

class _GpsPulseIndicatorState extends State<_GpsPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.4 + 0.6 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LiveDuration extends StatefulWidget {
  final DateTime startedAt;
  const _LiveDuration({required this.startedAt});

  @override
  State<_LiveDuration> createState() => _LiveDurationState();
}

class _LiveDurationState extends State<_LiveDuration> {
  late final Stream<int> _ticker = Stream<int>.periodic(
    const Duration(seconds: 1),
    (i) => i,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticker,
      builder: (context, _) {
        final d = DateTime.now().difference(widget.startedAt);
        final h = d.inHours;
        final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
        final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
        final formatted = h > 0 ? '$h:$m:$s' : '$m:$s';
        return Row(
          children: [
            const Icon(Icons.timer_outlined, size: 18),
            const SizedBox(width: 8),
            Text(formatted, style: Theme.of(context).textTheme.bodyLarge),
          ],
        );
      },
    );
  }
}
