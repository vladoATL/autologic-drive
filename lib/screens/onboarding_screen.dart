/// First-launch onboarding wizard. Walks the new driver through the
/// permissions and one-time setup the trip auto-detect needs to work,
/// then drops them on the main screen.
///
/// Sets `Preferences.onboardingDone = true` on completion so subsequent
/// logins go straight to `MainScreen`. Drivers can re-trigger it from
/// `SettingsScreen` (re-run wizard tile).
library;

import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../preferences.dart';
import '../tracking/engine.dart';
import '../trip/bluetooth_helper.dart';
import '../trip/vehicle.dart';
import '../trip/vehicle_label_dialog.dart';
import '../trip/vehicle_repository.dart';
import '../util/app_logger.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pages = PageController();
  int _index = 0;

  // Permission status snapshots — refreshed on init and on app resume.
  bool _locationGranted = false;
  bool _batteryGranted = false;
  bool _notifGranted = false;

  // Step 5 state
  List<BluetoothDevice> _pairedDevices = const [];
  bool _scanning = false;

  // Step 6 state
  bool _autoDetect = true;

  static const _stepCount = 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatuses();
    }
  }

  Future<void> _refreshPermissionStatuses() async {
    final results = await Future.wait([
      Permission.locationAlways.status,
      Permission.locationWhenInUse.status,
      Permission.ignoreBatteryOptimizations.status,
      Permission.notification.status,
    ]);
    if (!mounted) return;
    setState(() {
      // Allow either "always" (preferred) or "when in use" (good enough for
      // foreground-active driving, the engine just won't survive a screen-off).
      _locationGranted = results[0].isGranted || results[1].isGranted;
      _batteryGranted = results[2].isGranted;
      _notifGranted = results[3].isGranted;
    });
  }

  void _next() {
    if (_index >= _stepCount - 1) return;
    _pages.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_index <= 0) return;
    _pages.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    // Last-chance: if location was already granted from a previous run, the
    // user never tapped "Povoliť" so `_requestLocation()` (which also asks
    // for activity recognition + BLUETOOTH_CONNECT) never fired. Catch
    // that here so the MonitorService can actually start.
    final btConnect = await Permission.bluetoothConnect.status;
    if (!btConnect.isGranted) {
      final result = await Permission.bluetoothConnect.request();
      AppLogger.info('Onboarding finish: bluetoothConnect = $result');
    }
    final activity = await Permission.activityRecognition.status;
    if (!activity.isGranted) {
      final result = await Permission.activityRecognition.request();
      AppLogger.info('Onboarding finish: activityRecognition = $result');
    }
    // Kick the monitor service now that permissions are settled — onResume
    // of MainActivity will also retry, but this gives an instant start.
    await BluetoothHelper.startMonitorService();
    await Preferences.instance.setBool(Preferences.autoDetect, _autoDetect);
    await Preferences.instance.setBool(Preferences.onboardingDone, true);
    AppLogger.info('Onboarding completed (autoDetect=$_autoDetect)');
    widget.onFinished();
  }

  Future<void> _requestLocation() async {
    // Step 1: foreground permission. On Android < 11 this implicitly also
    // grants background.
    final inUse = await Permission.locationWhenInUse.request();
    AppLogger.info('Onboarding: locationWhenInUse = $inUse');

    if (inUse.isGranted) {
      // Step 2: background permission. On Android 11+ this opens the system
      // settings page where the user must pick "Allow all the time" manually.
      final always = await Permission.locationAlways.request();
      AppLogger.info('Onboarding: locationAlways = $always');

      // Step 3: activity recognition. Without it, Tracelet's motion detector
      // can't distinguish driving from idling and trip-start lags badly.
      final activity = await Permission.activityRecognition.request();
      AppLogger.info('Onboarding: activityRecognition = $activity');

      // Step 4: BLUETOOTH_CONNECT. Required by Android 14+ before the
      // background MonitorService can be promoted to foreground for BT
      // detection. Without it the service crashes at start.
      final btConnect = await Permission.bluetoothConnect.request();
      AppLogger.info('Onboarding: bluetoothConnect = $btConnect');
      if (btConnect.isGranted) {
        // The service skipped foreground promotion at app launch because
        // BT permission wasn't yet granted. Kick it off now.
        await BluetoothHelper.startMonitorService();
      }
    }

    // If anything is permanently denied (silent no-op on subsequent
    // requests), or whileInUse was denied, jump the user straight to the
    // app's permission page so they can fix it manually.
    final inUseAfter = await Permission.locationWhenInUse.status;
    final alwaysAfter = await Permission.locationAlways.status;
    final needsManual = inUseAfter.isPermanentlyDenied ||
        inUseAfter.isDenied ||
        alwaysAfter.isPermanentlyDenied;
    if (needsManual) {
      AppLogger.info('Onboarding: falling back to openAppSettings()');
      await openAppSettings();
    }
    await _refreshPermissionStatuses();
  }

  Future<void> _requestBattery() async {
    try {
      // Tracelet's openBatterySettings is unreliable from a non-tracking
      // state — go straight to the OS settings page via app_settings.
      await AppSettings.openAppSettings(
        type: AppSettingsType.batteryOptimization,
      );
    } catch (error) {
      AppLogger.warn('Battery optimization page open failed: $error');
      // Fallback: try Tracelet helper.
      try {
        await engine.requestIgnoreBatteryOptimizations();
      } catch (e) {
        AppLogger.warn('Tracelet battery fallback failed: $e');
      }
    }
  }

  Future<void> _requestNotifications() async {
    final result = await Permission.notification.request();
    AppLogger.info('Onboarding: notification permission = $result');
    await _refreshPermissionStatuses();
  }

  Future<void> _scanPaired() async {
    setState(() => _scanning = true);
    final ok = await BluetoothHelper.ensurePermissions();
    if (!ok) {
      if (mounted) setState(() => _scanning = false);
      return;
    }
    final on = await BluetoothHelper.isAdapterOn();
    if (!on) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _pairedDevices = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.vehicleAdapterOff),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final devices = await BluetoothHelper.bondedDevices();
    if (!mounted) return;
    setState(() {
      _pairedDevices = devices;
      _scanning = false;
    });
  }

  /// Same fat-Card layout as VehiclesScreen so the onboarding step and the
  /// in-app Vehicles screen render identically. Toggle ON creates the
  /// vehicle, edit-icon renames it, "Zrušiť priradenie" removes it.
  Widget _buildDeviceCard(BluetoothDevice d) {
    final loc = AppLocalizations.of(context)!;
    final existing = VehicleRepository.findByMac(d.address);
    final vehicle = existing ??
        Vehicle(
          bluetoothMac: d.address,
          bluetoothName: d.alias ?? d.name,
          label: d.alias ?? d.name ?? d.address,
        );
    final paired = existing != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  paired ? Icons.directions_car : Icons.bluetooth,
                  color: paired
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicle.label,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(d.alias ?? d.name ?? '',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(d.address,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final result = await promptVehicleLabel(
                      context,
                      initial: vehicle.label,
                    );
                    if (result == null) return;
                    await VehicleRepository.upsert(
                      vehicle.copyWith(label: result),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.vehicleAutoStartLabel),
              subtitle: Text(
                loc.vehicleAutoStartHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: d.address,
              groupValue: VehicleRepository.all()
                  .where((v) => v.autoStartTrip)
                  .map((v) => v.bluetoothMac)
                  .firstOrNull,
              onChanged: (selected) async {
                if (selected == null) return;
                if (!paired) {
                  await VehicleRepository.upsert(vehicle);
                }
                await VehicleRepository.setPrimaryAutoStart(selected);
                if (mounted) setState(() {});
              },
            ),
            if (paired)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await VehicleRepository.remove(d.address);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.link_off, size: 18),
                  label: Text(loc.vehicleUnlinkButton),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stepWelcome() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.primary,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/autologic_icon.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.onboardWelcomeTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.onboardWelcomeBody,
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _stepLocation() => _buildStep(
        icon: Icons.my_location,
        title: AppLocalizations.of(context)!.onboardLocationTitle,
        body: AppLocalizations.of(context)!.onboardLocationBody,
        action: _permissionAction(
          granted: _locationGranted,
          grantLabel: AppLocalizations.of(context)!.onboardGrantPermission,
          grantIcon: Icons.shield_outlined,
          onGrant: _requestLocation,
          onGrantedTap: () => openAppSettings(),
        ),
      );

  Widget _stepBattery() => _buildStep(
        icon: Icons.battery_charging_full,
        title: AppLocalizations.of(context)!.onboardBatteryTitle,
        body: AppLocalizations.of(context)!.onboardBatteryBody,
        action: _permissionAction(
          granted: _batteryGranted,
          grantLabel: AppLocalizations.of(context)!.onboardBatteryButton,
          grantIcon: Icons.settings,
          onGrant: _requestBattery,
          onGrantedTap: () => AppSettings.openAppSettings(
            type: AppSettingsType.batteryOptimization,
          ),
        ),
      );

  Widget _stepNotifications() => _buildStep(
        icon: Icons.notifications_active_outlined,
        title: AppLocalizations.of(context)!.onboardNotifTitle,
        body: AppLocalizations.of(context)!.onboardNotifBody,
        action: _permissionAction(
          granted: _notifGranted,
          grantLabel: AppLocalizations.of(context)!.onboardGrantPermission,
          grantIcon: Icons.shield_outlined,
          onGrant: _requestNotifications,
          onGrantedTap: () => AppSettings.openAppSettings(
            type: AppSettingsType.notification,
          ),
        ),
      );

  /// Renders either a primary "Grant permission" CTA or a green check tile
  /// confirming the permission is already enabled (with a quiet "Open
  /// settings" tap-target for the rare case the driver wants to revoke or
  /// re-prompt).
  Widget _permissionAction({
    required bool granted,
    required String grantLabel,
    required IconData grantIcon,
    required VoidCallback onGrant,
    required VoidCallback onGrantedTap,
  }) {
    final loc = AppLocalizations.of(context)!;
    if (granted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(loc.onboardPermissionGranted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onGrantedTap,
            icon: const Icon(Icons.settings, size: 16),
            label: Text(loc.onboardOpenSettings),
          ),
        ],
      );
    }
    return ElevatedButton.icon(
      onPressed: onGrant,
      icon: Icon(grantIcon),
      label: Text(grantLabel),
    );
  }

  Widget _stepBluetooth() {
    final loc = AppLocalizations.of(context)!;
    final paired = VehicleRepository.all();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bluetooth,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(loc.onboardBtTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(loc.onboardBtBody),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _scanning ? null : _scanPaired,
                icon: _scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(loc.onboardBtScan),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _pairedDevices.isEmpty
                ? Center(
                    child: Text(
                      paired.isEmpty
                          ? loc.onboardBtEmpty
                          : loc.onboardBtAlreadyPaired(paired.length),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: _pairedDevices.length,
                    itemBuilder: (_, i) => _buildDeviceCard(_pairedDevices[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stepAutoDetect() {
    final loc = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(loc.onboardAutoTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(loc.onboardAutoBody, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              title: Text(loc.autoDetectLabel),
              subtitle: Text(loc.autoDetectHint),
              value: _autoDetect,
              onChanged: (v) => setState(() => _autoDetect = v),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.touch_app, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.onboardManualTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(loc.onboardManualBody,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDone() => _buildStep(
        icon: Icons.celebration,
        title: AppLocalizations.of(context)!.onboardDoneTitle,
        body: AppLocalizations.of(context)!.onboardDoneBody,
      );

  Widget _buildStep({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 24),
            action,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final pages = <Widget>[
      _stepWelcome(),
      _stepLocation(),
      _stepBattery(),
      if (Platform.isAndroid) _stepNotifications(),
      _stepBluetooth(),
      _stepAutoDetect(),
      _stepDone(),
    ];
    final lastIndex = pages.length - 1;
    final reallyLast = _index == lastIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${pages.length}'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(loc.onboardSkip),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: pages,
              ),
            ),
            LinearProgressIndicator(
              value: (_index + 1) / pages.length,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _index > 0 ? _back : null,
                    icon: const Icon(Icons.chevron_left),
                    label: Text(loc.onboardBack),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: reallyLast ? _finish : _next,
                    icon: Icon(reallyLast
                        ? Icons.check
                        : Icons.chevron_right),
                    label: Text(reallyLast ? loc.onboardFinish : loc.onboardNext),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
