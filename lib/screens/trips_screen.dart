/// Kniha jázd — chronologický zoznam všetkých zaznamenaných jázd.
///
/// Tap on row → `TripDetailScreen`. Filter chips na vrchu zúžia zoznam na
/// nevyplnené alebo aktuálny mesiac. Overflow menu obsahuje *Exportovať
/// mesiac* (CSV cez share sheet).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../trip/trip_record.dart';
import '../trip/trip_repository.dart';
import '../util/trip_csv_exporter.dart';
import 'trip_detail_screen.dart';

enum _TripFilter { all, incomplete, thisMonth }

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  List<TripRecord> _trips = const [];
  bool _loading = true;
  _TripFilter _filter = _TripFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<TripRecord> trips;
    switch (_filter) {
      case _TripFilter.all:
        trips = await TripRepository.list();
      case _TripFilter.incomplete:
        trips = await TripRepository.list(incompleteOnly: true);
      case _TripFilter.thisMonth:
        final now = DateTime.now();
        final from = DateTime(now.year, now.month, 1);
        final to = DateTime(now.year, now.month + 1, 1);
        trips = await TripRepository.list(from: from, to: to);
    }
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _loading = false;
    });
  }

  Future<void> _exportThisMonth() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 1);
    final trips = await TripRepository.list(from: from, to: to);
    if (trips.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tripsExportEmpty)),
      );
      return;
    }
    await TripCsvExporter.shareCsv(trips, monthLabel: '${now.year}-${now.month.toString().padLeft(2, '0')}');
  }

  Widget _statusBadge(TripRecord t) {
    final loc = AppLocalizations.of(context)!;
    Color color;
    String label;
    IconData icon;
    if (t.isActive) {
      color = Colors.blue;
      label = loc.tripActive;
      icon = Icons.fiber_manual_record;
    } else if (!t.isComplete) {
      color = Colors.orange;
      label = loc.tripIncomplete;
      icon = Icons.warning_amber_outlined;
    } else {
      color = Colors.green;
      label = loc.tripComplete;
      icon = Icons.check_circle_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _tripTile(TripRecord t) {
    final fmt = DateFormat('d.M.yyyy HH:mm');
    final dur = t.endedAt?.difference(t.startedAt);
    final durLabel = dur == null
        ? '—'
        : (dur.inHours > 0
            ? '${dur.inHours} h ${dur.inMinutes.remainder(60)} min'
            : '${dur.inMinutes} min');
    final loc = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_car_outlined),
        title: Text(t.vehicleLabel ?? loc.tripWithoutVehicle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmt.format(t.startedAt)),
            const SizedBox(height: 4),
            Row(
              children: [
                _statusBadge(t),
                const SizedBox(width: 8),
                Text(
                  '$durLabel${t.distanceKm != null ? " · ${t.distanceKm!.toStringAsFixed(1)} km" : ""}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => TripDetailScreen(tripId: t.id),
            ),
          );
          if (changed == true) _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tripsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _exportThisMonth();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    const Icon(Icons.share, size: 20),
                    const SizedBox(width: 8),
                    Text(loc.tripsExportMonth),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _TripFilter.values)
                  ChoiceChip(
                    label: Text(_filterLabel(f, loc)),
                    selected: _filter == f,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _filter = f);
                        _load();
                      }
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _trips.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            loc.tripsEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _trips.length,
                          itemBuilder: (_, i) => _tripTile(_trips[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(_TripFilter f, AppLocalizations loc) {
    switch (f) {
      case _TripFilter.all:
        return loc.tripsFilterAll;
      case _TripFilter.incomplete:
        return loc.tripsFilterIncomplete;
      case _TripFilter.thisMonth:
        return loc.tripsFilterThisMonth;
    }
  }
}
