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
  name: 'AutoLogic (Starlogic)',
  url: 'http://autologic.starlogic.net:5055',
  apiUrl: 'http://autologic.starlogic.net:8082',
  backendApiUrl: 'http://autologic.starlogic.net:8080',
);

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
