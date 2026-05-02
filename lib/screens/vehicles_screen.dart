/// Vehicle pairing UI — list of paired Bluetooth devices, each editable
/// with a vehicle label + auto-start toggle.
library;

import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import '../l10n/app_localizations.dart';
import '../trip/bluetooth_helper.dart';
import '../trip/vehicle.dart';
import '../trip/vehicle_repository.dart';

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
    setState(() {
      _paired = devices;
      _loading = false;
    });
  }

  Future<void> _editLabel(Vehicle current) async {
    final controller = TextEditingController(text: current.label);
    final result = await showDialog<String>(
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.vehicleAutoStartLabel),
              subtitle: Text(
                AppLocalizations.of(context)!.vehicleAutoStartHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: vehicle.autoStartTrip,
              onChanged: (v) async {
                await VehicleRepository.upsert(
                  vehicle.copyWith(autoStartTrip: v),
                );
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
