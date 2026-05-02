import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'tracking/engine.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  Future<void> _refreshLogs() async {
    final logs = await engine.getLog();
    setState(() {
      _logs.clear();
      _logs.addAll(logs.split('\n'));
    });
  }

  Future<void> _emailLogs() async {
    await engine.emailLog("support@starlogic.net");
  }

  Future<void> _copyLogs() async {
    final text = await engine.getLog();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  Future<void> _clearLogs() async {
    await engine.destroyLog();
    setState(() => _logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.statusTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy to clipboard',
            onPressed: _copyLogs,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _emailLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        itemCount: _logs.length,
        itemBuilder: (_, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            _logs[index],
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
