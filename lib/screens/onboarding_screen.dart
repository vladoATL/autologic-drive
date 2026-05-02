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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatuses();
    }
  }

  Future<void> _refreshPermissionStatuses() async {
    final loc = await Permission.locationAlways.status;
    final locInUse = await Permission.locationWhenInUse.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    final notif = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      // Allow either "always" (preferred) or "when in use" (good enough for
      // foreground-active driving, the engine just won't survive a screen-off).
      _locationGranted = loc.isGranted || locInUse.isGranted;
      _batteryGranted = battery.isGranted;
      _notifGranted = notif.isGranted;
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
    await Preferences.instance.setBool(Preferences.autoDetect, _autoDetect);
    await Preferences.instance.setBool(Preferences.onboardingDone, true);
    AppLogger.info('Onboarding completed (autoDetect=$_autoDetect)');
    widget.onFinished();
  }

  Future<void> _requestLocation() async {
    final result = await [
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();
    AppLogger.info(
      'Onboarding: location permissions = ${result.entries.map((e) => "${e.key.toString().split('.').last}=${e.value}").join(", ")}',
    );
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

  Future<void> _pairAsVehicle(BluetoothDevice device) async {
    final controller = TextEditingController(
      text: device.alias ?? device.name ?? device.address,
    );
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.vehicleLabelHint),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Škoda Octavia BA123AB'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    await VehicleRepository.upsert(Vehicle(
      bluetoothMac: device.address,
      bluetoothName: device.alias ?? device.name,
      label: label,
      autoStartTrip: true,
    ));
    AppLogger.info('Onboarding: paired vehicle ${device.address} as $label');
    if (mounted) setState(() {});
  }

  Future<void> _editVehicle(BluetoothDevice device, Vehicle existing) async {
    final loc = AppLocalizations.of(context)!;
    final deviceName = device.alias ?? device.name ?? device.address;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    device.address,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(loc.vehicleRenameAction),
              subtitle: Text(existing.label),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome),
              title: Text(loc.vehicleAutoStartLabel),
              value: existing.autoStartTrip,
              onChanged: (v) => Navigator.pop(ctx, v ? 'auto_on' : 'auto_off'),
            ),
            ListTile(
              leading: Icon(Icons.link_off,
                  color: Theme.of(context).colorScheme.error),
              title: Text(loc.vehicleUnlinkButton),
              onTap: () => Navigator.pop(ctx, 'unlink'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'rename':
        await _pairAsVehicle(device);
        break;
      case 'auto_on':
        await VehicleRepository.upsert(existing.copyWith(autoStartTrip: true));
        AppLogger.info('Vehicle ${existing.label} autoStart=true');
        if (mounted) setState(() {});
        break;
      case 'auto_off':
        await VehicleRepository.upsert(existing.copyWith(autoStartTrip: false));
        AppLogger.info('Vehicle ${existing.label} autoStart=false');
        if (mounted) setState(() {});
        break;
      case 'unlink':
        await VehicleRepository.remove(existing.bluetoothMac);
        AppLogger.info('Vehicle ${existing.label} unlinked');
        if (mounted) setState(() {});
        break;
    }
  }

  Widget _stepWelcome() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurface,
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
                    itemBuilder: (_, i) {
                      final d = _pairedDevices[i];
                      final existing =
                          VehicleRepository.findByMac(d.address);
                      return Card(
                        child: ListTile(
                          leading: Icon(existing != null
                              ? (existing.autoStartTrip
                                  ? Icons.directions_car
                                  : Icons.bluetooth_disabled)
                              : Icons.bluetooth),
                          title: Text(existing?.label ??
                              d.alias ??
                              d.name ??
                              d.address),
                          subtitle: Text(
                            existing != null
                                ? '${d.address} · ${existing.autoStartTrip ? loc.vehicleAutoStartLabel : "auto-štart vypnutý"}'
                                : d.address,
                          ),
                          trailing: existing != null
                              ? const Icon(Icons.more_vert)
                              : TextButton(
                                  onPressed: () => _pairAsVehicle(d),
                                  child: Text(loc.onboardBtPickButton),
                                ),
                          onTap: existing != null
                              ? () => _editVehicle(d, existing)
                              : () => _pairAsVehicle(d),
                        ),
                      );
                    },
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
