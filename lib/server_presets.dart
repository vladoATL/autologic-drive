class ServerPreset {
  final String name;
  final String url;
  const ServerPreset({required this.name, required this.url});
}

const ServerPreset kAutoLogicServer = ServerPreset(
  name: 'AutoLogic (Starlogic)',
  url: 'http://autologic.starlogic.net:5055',
);

const List<ServerPreset> kServerPresets = [
  kAutoLogicServer,
  ServerPreset(name: 'Traccar Demo', url: 'http://demo.traccar.org:5055'),
];

ServerPreset? matchPreset(String? url) {
  if (url == null) return null;
  for (final preset in kServerPresets) {
    if (preset.url == url) return preset;
  }
  return null;
}
