import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:autologic_drive/main.dart';
import 'package:autologic_drive/password_service.dart';
import 'package:autologic_drive/qr_code_screen.dart';
import 'package:autologic_drive/tracking/engine.dart';
import 'package:wakelock_partial_android/wakelock_partial_android.dart';

import 'l10n/app_localizations.dart';
import 'preferences.dart';
import 'server_presets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool advanced = false;

  String _getAccuracyLabel(String? key) {
    return switch (key) {
      'highest' => AppLocalizations.of(context)!.highestAccuracyLabel,
      'high' => AppLocalizations.of(context)!.highAccuracyLabel,
      'low' => AppLocalizations.of(context)!.lowAccuracyLabel,
      _ => AppLocalizations.of(context)!.mediumAccuracyLabel,
    };
  }

  Future<void> _editSetting(String title, String key, bool isInt) async {
    final initialValue = isInt
        ? Preferences.instance.getInt(key)?.toString() ?? '0'
        : Preferences.instance.getString(key) ?? '';

    final controller = TextEditingController(text: initialValue);
    final errorMessage = AppLocalizations.of(context)!.invalidValue;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: isInt ? TextInputType.number : TextInputType.text,
          inputFormatters: isInt ? [FilteringTextInputFormatter.digitsOnly] : [],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (key == Preferences.url) {
        final uri = Uri.tryParse(result);
        if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
          messengerKey.currentState?.showSnackBar(SnackBar(content: Text(errorMessage)));
          return;
        }
      }
      if (isInt) {
        int? intValue = int.tryParse(result);
        if (intValue != null) {
          if (key == Preferences.heartbeat && intValue > 0 && intValue < 60) {
            intValue = 60; // minimum heartbeat is 60 seconds
          }
          await Preferences.instance.setInt(key, intValue);
        }
      } else {
        await Preferences.instance.setString(key, result);
      }
      await engine.setConfig(Preferences.trackingConfig(true));
      setState(() {});
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: AppLocalizations.of(context)!.passwordLabel),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        ],
      ),
    );
    if (result == true) {
      await PasswordService.setPassword(controller.text);
    }
  }

  Widget _buildListTile(String title, String key, bool isInt) {
    String? value;
    if (isInt) {
      final intValue = Preferences.instance.getInt(key);
      if (intValue != null && intValue > 0) {
        value = intValue.toString();
      } else {
        value = AppLocalizations.of(context)!.disabledValue;
      }
    } else {
      value = Preferences.instance.getString(key);
    }
    return ListTile(
      title: Text(title),
      subtitle: Text(value ?? ''),
      onTap: () => _editSetting(title, key, isInt),
    );
  }

  Future<void> _editCustomUrl() async {
    final controller = TextEditingController(
      text: Preferences.instance.getString(Preferences.url) ?? '',
    );
    final errorMessage = AppLocalizations.of(context)!.invalidValue;
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(AppLocalizations.of(context)!.urlLabel),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final uri = Uri.tryParse(saved);
    if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }
    await Preferences.instance.setString(Preferences.url, saved);
    await engine.setConfig(Preferences.trackingConfig(true));
    if (mounted) setState(() {});
  }

  Widget _buildUrlListTile() {
    final currentUrl = Preferences.instance.getString(Preferences.url);
    final preset = matchPreset(currentUrl);
    final subtitle = preset != null ? '${preset.name} — ${preset.url}' : (currentUrl ?? '');
    return ListTile(
      title: Text(AppLocalizations.of(context)!.urlLabel),
      subtitle: Text(subtitle),
      onTap: () async {
        final selection = await showModalBottomSheet<Object>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in kServerPresets)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.url),
                    trailing: currentUrl == p.url ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, p),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Custom'),
                  trailing: matchPreset(currentUrl) == null && currentUrl != null && currentUrl.isNotEmpty
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, 'custom'),
                ),
              ],
            ),
          ),
        );
        if (selection is ServerPreset) {
          await Preferences.instance.setString(Preferences.url, selection.url);
          await engine.setConfig(Preferences.trackingConfig(true));
          if (mounted) setState(() {});
        } else if (selection == 'custom') {
          await _editCustomUrl();
        }
      },
    );
  }

  Widget _buildLanguageListTile() {
    const options = <(String, String)>[
      ('sk', 'Slovenčina'),
      ('cs', 'Čeština'),
      ('en', 'English'),
    ];
    final current = Preferences.instance.getString(Preferences.language) ?? 'sk';
    final currentLabel = options.firstWhere(
      (o) => o.$1 == current,
      orElse: () => options.first,
    ).$2;
    return ListTile(
      title: Text(AppLocalizations.of(context)!.languageLabel),
      subtitle: Text(currentLabel),
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(AppLocalizations.of(context)!.languageLabel),
            children: [
              for (final o in options)
                SimpleDialogOption(
                  child: Row(
                    children: [
                      Expanded(child: Text(o.$2)),
                      if (o.$1 == current) const Icon(Icons.check),
                    ],
                  ),
                  onPressed: () => Navigator.pop(context, o.$1),
                ),
            ],
          ),
        );
        if (picked != null) {
          await Preferences.instance.setString(Preferences.language, picked);
          appLocale.value = Locale(picked);
          if (mounted) setState(() {});
        }
      },
    );
  }

  Widget _buildAccuracyListTile() {
    final accuracyOptions = ['highest', 'high', 'medium', 'low'];
    return ListTile(
      title: Text(AppLocalizations.of(context)!.accuracyLabel),
      subtitle: Text(_getAccuracyLabel(Preferences.instance.getString(Preferences.accuracy))),
      onTap: () async {
        final selectedAccuracy = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(AppLocalizations.of(context)!.accuracyLabel),
            children: accuracyOptions.map((option) => SimpleDialogOption(
              child: Text(_getAccuracyLabel(option)),
              onPressed: () => Navigator.pop(context, option),
            )).toList(),
          ),
        );
        if (selectedAccuracy != null) {
          await Preferences.instance.setString(Preferences.accuracy, selectedAccuracy);
          await engine.setConfig(Preferences.trackingConfig(true));
          setState(() {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHighestAccuracy = Preferences.instance.getString(Preferences.accuracy) == 'highest';
    final distance = Preferences.instance.getInt(Preferences.distance);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settingsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const QrCodeScreen()));
              setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildLanguageListTile(),
          _buildListTile(AppLocalizations.of(context)!.idLabel, Preferences.id, false),
          _buildUrlListTile(),
          _buildAccuracyListTile(),
          _buildListTile(AppLocalizations.of(context)!.distanceLabel, Preferences.distance, true),
          if (isHighestAccuracy || Platform.isAndroid && distance == 0)
            _buildListTile(AppLocalizations.of(context)!.intervalLabel, Preferences.interval, true),
          if (isHighestAccuracy)
            _buildListTile(AppLocalizations.of(context)!.angleLabel, Preferences.angle, true),
          _buildListTile(AppLocalizations.of(context)!.heartbeatLabel, Preferences.heartbeat, true),
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.advancedLabel),
            value: advanced,
            onChanged: (value) {
              setState(() => advanced = value);
            },
          ),
          if (advanced)
            _buildListTile(AppLocalizations.of(context)!.fastestIntervalLabel, Preferences.fastestInterval, true),
          if (advanced)
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.bufferLabel),
              value: Preferences.instance.getBool(Preferences.buffer) ?? true,
              onChanged: (value) async {
                await Preferences.instance.setBool(Preferences.buffer, value);
                await engine.setConfig(Preferences.trackingConfig(true));
                setState(() {});
              },
            ),
          if (advanced && Platform.isAndroid)
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.wakelockLabel),
              value: Preferences.instance.getBool(Preferences.wakelock) ?? false,
              onChanged: (value) async {
                await Preferences.instance.setBool(Preferences.wakelock, value);
                if (value) {
                  final state = await engine.getState();
                  if (state.isMoving == true) {
                    WakelockPartialAndroid.acquire();
                  }
                } else {
                  WakelockPartialAndroid.release();
                }
                setState(() {});
              },
            ),
          if (advanced)
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.stopDetectionLabel),
              value: Preferences.instance.getBool(Preferences.stopDetection) ?? true,
              onChanged: (value) async {
                await Preferences.instance.setBool(Preferences.stopDetection, value);
                await engine.setConfig(Preferences.trackingConfig(true));
                setState(() {});
              },
            ),
          if (advanced)
            ListTile(
              title: Text(AppLocalizations.of(context)!.passwordLabel),
              onTap: _changePassword,
            ),
          ListTile(
            leading: const Icon(Icons.replay),
            title: Text(AppLocalizations.of(context)!.onboardRerun),
            onTap: () async {
              final navigator = Navigator.of(context);
              await Preferences.instance.setBool(Preferences.onboardingDone, false);
              needsOnboarding.value = true;
              if (!mounted) return;
              navigator.pop();
            },
          ),
        ],
      ),
    );
  }
}
