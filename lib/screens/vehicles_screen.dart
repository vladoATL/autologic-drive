/// Vehicle pairing UI — list of paired Bluetooth devices, each editable
/// with a vehicle label + auto-start toggle.
library;

import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import '../l10n/app_localizations.dart';
import '../trip/bluetooth_helper.dart';
import '../trip/vehicle.dart';
import '../trip/vehicle_label_dialog.dart';
import '../trip/vehicle_repository.dart';
import '../util/app_logger.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  List<BluetoothDevice> _paired = const [];
  bool _loading = true;
  bool _adapterOff = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _adapterOff = false;
    });
    final granted = await BluetoothHelper.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final on = await BluetoothHelper.isAdapterOn();
    if (!on) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _adapterOff = true;
      });
      return;
    }
    final devices = await BluetoothHelper.bondedDevices();
    if (!mounted) return;
    final all = VehicleRepository.all();
    final hasPrimary = all.any((v) => v.autoStartTrip);
    AppLogger.info(
      'Vehicles refresh: bonded=${devices.length} ${devices.map((d) => "${d.alias ?? d.name}/${d.address}").join(",")} '
      'repoVehicles=${all.length} '
      'repoAutoStart=${all.where((v) => v.autoStartTrip).map((v) => v.label).join(",")} '
      'hasPrimary=$hasPrimary',
    );
    // Pick a primary auto-start vehicle automatically when there's a clear
    // candidate. Skip OBD readers and accessories (SmartBox, ELM327, OBDII,
    // headphones, smart watches, beacons) — those have BT but aren't the
    // car's head-unit. If after filtering exactly one candidate remains,
    // promote it.
    if (!hasPrimary) {
      final candidates = devices.where((d) {
        final name = (d.alias ?? d.name ?? '').toLowerCase();
        const accessoryHints = [
          'smartbox', 'elm', 'obd', 'obdii', 'headphone', 'headset',
          'airpods', 'watch', 'band', 'beacon', 'tile', 'tag',
          'speaker', 'mouse', 'keyboard',
        ];
        return !accessoryHints.any(name.contains);
      }).toList();
      AppLogger.info(
        'Vehicles auto-promote: ${candidates.length} candidate(s) after filter '
        '${candidates.map((d) => d.alias ?? d.name).join(",")}',
      );
      if (candidates.length == 1) {
        final d = candidates.first;
        if (VehicleRepository.findByMac(d.address) == null) {
          await VehicleRepository.upsert(Vehicle(
            bluetoothMac: d.address,
            bluetoothName: d.alias ?? d.name,
            label: d.alias ?? d.name ?? d.address,
          ));
          AppLogger.info('Vehicles: created Vehicle row for ${d.address}');
        }
        await VehicleRepository.setPrimaryAutoStart(d.address);
        AppLogger.info('Vehicles: auto-promoted ${d.address} as primary');
      }
    }
    if (!mounted) return;
    setState(() {
      _paired = devices;
      _loading = false;
    });
  }

  Future<void> _editLabel(Vehicle current) async {
    final result = await promptVehicleLabel(context, initial: current.label);
    if (result == null) return;
    await VehicleRepository.upsert(current.copyWith(label: result));
    if (mounted) setState(() {});
  }

  Widget _buildDeviceTile(BluetoothDevice d) {
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
                  onPressed: () => _editLabel(vehicle),
                ),
              ],
            ),
            // Single-select across all paired devices: tapping the radio
            // promotes this BT to the trigger and clears every other
            // vehicle's autoStartTrip. Stops the SmartBox + Karoq tug-of-war
            // that caused trips to flap on the 2026-05-04 morning test.
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.vehicleAutoStartLabel),
              subtitle: Text(
                AppLocalizations.of(context)!.vehicleAutoStartHint,
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
                  label: Text(AppLocalizations.of(context)!.vehicleUnlinkButton),
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
        title: Text(AppLocalizations.of(context)!.vehiclesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _adapterOff
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppLocalizations.of(context)!.vehicleAdapterOff,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _paired.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          AppLocalizations.of(context)!.vehicleNoPairedDevices,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: _paired.map(_buildDeviceTile).toList(),
                    ),
    );
  }
}
