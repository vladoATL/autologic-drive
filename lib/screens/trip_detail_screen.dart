/// Edit screen for one trip in the kniha jázd. Driver fills in legally-required
/// fields here (driver name, purpose, business/private, odometer pre/po).
///
/// Reachable from: TripsScreen list tap, trip-stop notification deep link,
/// or trip-start notification (so the driver can capture odometer-pred
/// while still in the parking spot).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../trip/trip_record.dart';
import '../trip/trip_repository.dart';
import '../util/address_resolver.dart';

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

  late final TextEditingController _driverCtrl = TextEditingController();
  late final TextEditingController _purposeCtrl = TextEditingController();
  late final TextEditingController _odoStartCtrl = TextEditingController();
  late final TextEditingController _odoEndCtrl = TextEditingController();
  TripKind _kind = TripKind.business;

  List<String> _driverSuggestions = const [];
  bool _odoEndManuallyEdited = false;

  static const _purposePresets = <String>[
    'Stretnutie',
    'Servis',
    'Klient',
    'Nákup',
    'Montáž',
    'Iné',
  ];

  @override
  void initState() {
    super.initState();
    _odoStartCtrl.addListener(_maybeFillOdometerEnd);
    // NOTE: `_odoEndManuallyEdited` is flipped from the TextField.onChanged
    // handler (user input only), NOT from a controller listener. A listener
    // would fire when our own auto-fill writes into the controller and
    // self-poison the flag, freezing future auto-fills.
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      TripRepository.findById(widget.tripId),
      TripRepository.distinctDriverNames(),
    ]);
    if (!mounted) return;
    final t = results[0] as TripRecord?;
    final names = results[1] as List<String>;
    if (t == null) {
      setState(() => _loading = false);
      return;
    }
    _driverCtrl.text = t.driverName ?? '';
    _purposeCtrl.text = t.purpose;
    // Pre-fill Tacho pred from the previous trip's Tacho po (same vehicle).
    // Only when the current trip doesn't already have its own value typed.
    int? odoStart = t.odometerStart;
    if (odoStart == null && t.vehicleMac != null) {
      final prev = await TripRepository.lastCompletedWithOdoForVehicle(
        t.vehicleMac!,
        excludeId: t.id,
      );
      if (prev?.odometerEnd != null) {
        odoStart = prev!.odometerEnd;
      }
    }
    _odoStartCtrl.text = odoStart?.toString() ?? '';
    _odoEndCtrl.text = t.odometerEnd?.toString() ?? '';
    _odoEndManuallyEdited = t.odometerEnd != null;
    _kind = t.kind;
    setState(() {
      _trip = t;
      _driverSuggestions = names;
      _loading = false;
    });
    _maybeResolveAddresses(t);
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

  /// When the driver fills in the start odometer and the end is still empty,
  /// suggest `start + round(distanceKm)`. The driver can override; once they
  /// type into the end field manually we stop auto-filling.
  void _maybeFillOdometerEnd() {
    if (_odoEndManuallyEdited) return;
    final t = _trip;
    if (t == null || t.distanceKm == null) return;
    final start = int.tryParse(_odoStartCtrl.text.trim());
    if (start == null) return;
    final suggested = start + t.distanceKm!.round();
    final current = _odoEndCtrl.text;
    final newText = suggested.toString();
    if (current == newText) return;
    _odoEndCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  @override
  void dispose() {
    _driverCtrl.dispose();
    _purposeCtrl.dispose();
    _odoStartCtrl.dispose();
    _odoEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _trip;
    if (t == null) return;
    final updated = t.copyWith(
      driverName: _driverCtrl.text.trim(),
      purpose: _purposeCtrl.text.trim(),
      kind: _kind,
      odometerStart: int.tryParse(_odoStartCtrl.text.trim()),
      odometerEnd: int.tryParse(_odoEndCtrl.text.trim()),
    );
    await TripRepository.update(updated);
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _driverCtrl.text),
            optionsBuilder: (input) {
              if (input.text.isEmpty) return _driverSuggestions;
              final q = input.text.toLowerCase();
              return _driverSuggestions
                  .where((n) => n.toLowerCase().contains(q));
            },
            onSelected: (v) => _driverCtrl.text = v,
            fieldViewBuilder: (ctx, controller, focusNode, _) {
              // Mirror the autocomplete's controller back into our state
              // controller so `_save()` reads the latest value.
              controller.addListener(() => _driverCtrl.text = controller.text);
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: loc.tripDriverLabel,
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purposeCtrl,
            decoration: InputDecoration(
              labelText: loc.tripPurposeLabel,
              hintText: loc.tripPurposeHint,
              prefixIcon: const Icon(Icons.flag_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in _purposePresets)
                ActionChip(
                  label: Text(preset),
                  onPressed: () {
                    _purposeCtrl.text = preset;
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<TripKind>(
            segments: [
              ButtonSegment(
                value: TripKind.business,
                label: Text(loc.tripKindBusiness),
                icon: const Icon(Icons.work_outline),
              ),
              ButtonSegment(
                value: TripKind.private,
                label: Text(loc.tripKindPrivate),
                icon: const Icon(Icons.home_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (sel) => setState(() => _kind = sel.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _odoStartCtrl,
                  decoration: InputDecoration(
                    labelText: loc.tripOdoStartLabel,
                    border: const OutlineInputBorder(),
                    suffixText: 'km',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _odoEndCtrl,
                  decoration: InputDecoration(
                    labelText: loc.tripOdoEndLabel,
                    border: const OutlineInputBorder(),
                    suffixText: 'km',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _odoEndManuallyEdited = true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(loc.saveButton),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
