class ServerPreset {
  final String name;
  final String url;            // OsmAnd ingest endpoint (port 5055)
  final String apiUrl;         // Traccar REST API (port 8082 in dev, https in prod)
  final String backendApiUrl;  // AutoLogic Backend (.NET 10, port 8080)
  const ServerPreset({
    required this.name,
    required this.url,
    required this.apiUrl,
    required this.backendApiUrl,
  });
}

const ServerPreset kAutoLogicServer = ServerPreset(
  name: 'AutoLogic',
  url: 'http://api.autologic.sk:5055',
  apiUrl: 'http://api.autologic.sk:8082',
  backendApiUrl: 'http://api.autologic.sk:8080',
);

/// Pre-0.17.0 preset values, kept around for migration so existing installs
/// auto-switch when they next start the app.
const kLegacyAutoLogicHosts = <String>[
  'autologic.starlogic.net',
  // localhost was used during dev — also bumped to the new prod host on
  // upgrade so the user doesn't have to manually fix Settings → Server URL.
  'localhost',
];

const List<ServerPreset> kServerPresets = [
  kAutoLogicServer,
  ServerPreset(
    name: 'Traccar Demo',
    url: 'http://demo.traccar.org:5055',
    apiUrl: 'https://demo.traccar.org',
    backendApiUrl: '', // demo Traccar doesn't have a backend
  ),
];

ServerPreset? matchPreset(String? url) {
  if (url == null) return null;
  for (final preset in kServerPresets) {
    if (preset.url == url) return preset;
  }
  return null;
}
