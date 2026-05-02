/// Shared label-prompt dialog used by both `OnboardingScreen` and
/// `VehiclesScreen`. Returns the trimmed label, or `null` if the driver
/// cancelled / left it empty.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

Future<String?> promptVehicleLabel(
  BuildContext context, {
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final loc = AppLocalizations.of(context)!;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.vehicleLabelHint),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Škoda Octavia BA123AB'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.cancelButton),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(loc.saveButton),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return null;
  return result;
}
