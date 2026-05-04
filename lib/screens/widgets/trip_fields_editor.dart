/// Editable kniha-jázd fields for one trip — driver autocomplete, purpose
/// (free text + chips), business/private, odometer pred/po. Auto-saves to
/// SQLite with an 800 ms debounce so the driver can type freely without
/// needing a Save button.
///
/// Used by:
/// - `TripDetailScreen` (post-trip edit)
/// - `MainScreen` inline trip card while a trip is active (so the driver
///   can fill in tacho pred and purpose without leaving the home screen)
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../trip/trip_record.dart';
import '../../trip/trip_repository.dart';

class TripFieldsEditor extends StatefulWidget {
  final String tripId;
  final EdgeInsetsGeometry padding;

  const TripFieldsEditor({
    super.key,
    required this.tripId,
    this.padding = const EdgeInsets.all(0),
  });

  @override
  State<TripFieldsEditor> createState() => _TripFieldsEditorState();
}

class _TripFieldsEditorState extends State<TripFieldsEditor> {
  TripRecord? _trip;
  bool _loading = true;

  late final TextEditingController _driverCtrl = TextEditingController();
  late final TextEditingController _purposeCtrl = TextEditingController();
  late final TextEditingController _odoStartCtrl = TextEditingController();
  late final TextEditingController _odoEndCtrl = TextEditingController();
  TripKind _kind = TripKind.business;

  List<String> _driverSuggestions = const [];
  bool _odoEndManuallyEdited = false;
  Timer? _saveTimer;

  static const _purposePresets = <String>[
    'Stretnutie',
    'Servis',
    'Klient',
    'Nákup',
    'Montáž',
    'Iné',
  ];

  static const _saveDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _odoStartCtrl.addListener(_maybeFillOdometerEnd);
    _load();
  }

  @override
  void didUpdateWidget(covariant TripFieldsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) {
      // Different trip — reload (e.g. user stops + auto-starts another trip
      // while staying on MainScreen).
      _load();
    }
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
  }

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

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _save);
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
    if (mounted) _trip = updated;
  }

  /// Force-flush any pending debounced save (called by hosting screens
  /// when they're about to dispose).
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer?.cancel();
      await _save();
    }
  }

  @override
  void dispose() {
    flush();
    _driverCtrl.dispose();
    _purposeCtrl.dispose();
    _odoStartCtrl.dispose();
    _odoEndCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_trip == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _driverCtrl.text),
            optionsBuilder: (input) {
              if (input.text.isEmpty) return _driverSuggestions;
              final q = input.text.toLowerCase();
              return _driverSuggestions
                  .where((n) => n.toLowerCase().contains(q));
            },
            onSelected: (v) {
              _driverCtrl.text = v;
              _scheduleSave();
            },
            fieldViewBuilder: (ctx, controller, focusNode, _) {
              controller.addListener(() {
                if (_driverCtrl.text != controller.text) {
                  _driverCtrl.text = controller.text;
                  _scheduleSave();
                }
              });
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
            onChanged: (_) => _scheduleSave(),
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
                    _scheduleSave();
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
            onSelectionChanged: (sel) {
              setState(() => _kind = sel.first);
              _scheduleSave();
            },
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
                  onChanged: (_) => _scheduleSave(),
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
                  onChanged: (_) {
                    _odoEndManuallyEdited = true;
                    _scheduleSave();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
