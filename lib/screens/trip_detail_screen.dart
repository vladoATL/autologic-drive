/// Edit screen for one trip in the kniha jázd. Driver fills in legally-required
/// fields here (driver name, purpose, business/private, odometer pre/po).
///
/// Reachable from: TripsScreen list tap, trip-stop notification deep link,
/// or trip-start notification (so the driver can capture odometer-pred
/// while still in the parking spot).
///
/// As of 0.14.0 the editable fields live in [TripFieldsEditor] (auto-save,
/// no Save button) so the same widget can be embedded inline on
/// MainScreen during an active trip.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../trip/trip_record.dart';
import '../trip/trip_repository.dart';
import '../util/address_resolver.dart';
import 'widgets/trip_fields_editor.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  TripRecord? _trip;
  bool _loading = true;
  bool _resolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await TripRepository.findById(widget.tripId);
    if (!mounted) return;
    setState(() {
      _trip = t;
      _loading = false;
    });
    if (t != null) _maybeResolveAddresses(t);
  }

  Future<void> _maybeResolveAddresses(TripRecord t) async {
    final needsResolve =
        (t.startAddress == null && t.startLat != null && t.startLng != null) ||
            (t.endAddress == null && t.endLat != null && t.endLng != null);
    if (!needsResolve) return;
    setState(() => _resolvingAddress = true);
    final updated = await AddressResolver.resolveAndPersist(t);
    if (!mounted) return;
    setState(() {
      _trip = updated;
      _resolvingAddress = false;
    });
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.tripDeleteTitle),
        content: Text(loc.tripDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.tripDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TripRepository.delete(widget.tripId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _addressRow({
    required IconData icon,
    required String label,
    required String? address,
    required bool hasCoords,
    required AppLocalizations loc,
  }) {
    final String value;
    if (address != null && address.isNotEmpty) {
      value = address;
    } else if (_resolvingAddress && hasCoords) {
      value = loc.tripAddressResolving;
    } else {
      value = '—';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 6),
        Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.tripDetailTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final t = _trip;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.tripDetailTitle)),
        body: Center(child: Text(loc.tripNotFound)),
      );
    }

    final fmt = DateFormat('d.M.yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tripDetailTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: loc.tripDeleteAction,
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.directions_car_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.vehicleLabel ?? loc.tripWithoutVehicle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(t.startedAt)}'
                    '${t.endedAt != null ? "  →  ${fmt.format(t.endedAt!)}" : "  →  ${loc.tripActive}"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (t.distanceKm != null)
                    Text('${t.distanceKm!.toStringAsFixed(1)} km'),
                  const SizedBox(height: 8),
                  _addressRow(
                    icon: Icons.trip_origin,
                    label: loc.tripStartAddress,
                    address: t.startAddress,
                    hasCoords: t.startLat != null && t.startLng != null,
                    loc: loc,
                  ),
                  const SizedBox(height: 4),
                  _addressRow(
                    icon: Icons.location_on_outlined,
                    label: loc.tripEndAddress,
                    address: t.endAddress,
                    hasCoords: t.endLat != null && t.endLng != null,
                    loc: loc,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TripFieldsEditor(tripId: widget.tripId),
          const SizedBox(height: 24),
          // Auto-save already persists every edit on an 800 ms debounce, so
          // this button is purely navigation back to home — but drivers
          // expect a visible "I'm done" confirmation after typing tacho po
          // and purpose, otherwise it's not obvious the form is saved.
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: Text(loc.tripDoneButton),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
