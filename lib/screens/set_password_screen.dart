/// Shown right after a successful QR pairing. Lets the driver set a password
/// for later web-admin login. Skippable — the driver can postpone it and use
/// the same screen later from Settings.
library;

import 'package:flutter/material.dart';

import '../auth/backend_api.dart';
import '../preferences.dart';

class SetPasswordScreen extends StatefulWidget {
  /// True when shown right after pairing (renders "Preskočiť"). False when the
  /// user opens it from Settings to change an existing password.
  final bool skippable;
  const SetPasswordScreen({super.key, this.skippable = true});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pwd = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pwd.length < 8) {
      setState(() => _error = 'Heslo musí mať minimálne 8 znakov');
      return;
    }
    if (pwd != confirm) {
      setState(() => _error = 'Heslá sa nezhodujú');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendApi.setPassword(pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Heslo nastavené')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Nepodarilo sa uložiť heslo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Preferences.instance.getString(Preferences.authEmail) ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nastaviť heslo'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Nastav si heslo, aby si sa neskôr mohol prihlásiť na webovú aplikáciu Kniha jázd.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  if (email.isNotEmpty) ...[
                    Text('Email: $email',
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'Nové heslo',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Potvrdiť heslo',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Ukladám…' : 'Uložiť heslo'),
                  ),
                  if (widget.skippable) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Preskočiť'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
