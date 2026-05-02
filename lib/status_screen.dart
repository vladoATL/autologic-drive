import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'tracking/engine.dart';
import 'util/app_logger.dart';

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

  Future<String> _combinedLogs() async {
    final app = await AppLogger.read();
    final sdk = await engine.getLog();
    final buf = StringBuffer();
    if (app.isNotEmpty) {
      buf.writeln('=== AutoLogic Drive ===');
      buf.writeln(app);
      buf.writeln();
    }
    if (sdk.isNotEmpty) {
      buf.writeln('=== Tracelet SDK ===');
      buf.writeln(sdk);
    }
    return buf.toString();
  }

  Future<void> _refreshLogs() async {
    final text = await _combinedLogs();
    setState(() {
      _logs.clear();
      _logs.addAll(text.split('\n'));
    });
  }

  Future<void> _emailLogs() async {
    await engine.emailLog("support@starlogic.net");
  }

  Future<void> _copyLogs() async {
    final text = await _combinedLogs();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  Future<void> _clearLogs() async {
    await engine.destroyLog();
    await AppLogger.clear();
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
