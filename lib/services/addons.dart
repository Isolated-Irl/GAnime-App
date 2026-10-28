// Addons manager — Stremio protocol, user-installed ONLY.
// GAnime never bundles, hosts, lists, or recommends stream sources.
// The user pastes a manifest URL they found themselves; the app only
// fetches that manifest and then queries that addon's own /stream/ API.
// No example addon names or URLs are shipped in this app.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class AddonsService {
  static String normalizeManifestUrl(String input) {
    var u = input.trim();
    if (u.startsWith('stremio://')) {
      u = u.replaceFirst('stremio://', 'https://');
    }
    if (!u.endsWith('/manifest.json')) u += '/manifest.json';
    return u;
  }

  static String baseOf(String manifestUrl) =>
      manifestUrl.replaceAll(RegExp(r'/manifest\.json$', caseSensitive: false), '');

  static Future<AddonRecord> fetchManifest(String input) async {
    final url = normalizeManifestUrl(input);
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      throw Exception('Manifest fetch failed (${r.statusCode})');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['id'] == null || j['name'] == null) {
      throw Exception('Not a valid addon manifest (missing id/name)');
    }
    return AddonRecord(
      manifestUrl: url,
      baseUrl: baseOf(url),
      id: '${j['id']}',
      name: '${j['name']}',
      version: (j['version'] as String?) ?? '',
      addedAt: DateTime.now(),
    );
  }

  /// Streams for one title from one addon.
  /// [streamId] is the Stremio id, e.g. `anilist:123:1` for anime addons.
  /// Addons that declare only `series` use the same id form; the addon
  /// itself decides what it can resolve.
  static Future<List<StreamSource>> streams(
      AddonRecord addon, String type, String streamId) async {
    final url = '${addon.baseUrl}/stream/$type/$streamId.json';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final out = <StreamSource>[];
    for (final s in (j['streams'] as List?) ?? []) {
      final m = s as Map<String, dynamic>;
      final streamUrl = (m['url'] as String?) ?? (m['externalUrl'] as String?);
      if (streamUrl == null || streamUrl.isEmpty) continue;
      out.add(StreamSource(
        name: (m['name'] as String?) ?? addon.name,
        url: streamUrl,
        quality: (m['description'] as String?) ?? '',
      ));
    }
    return out;
  }
}
