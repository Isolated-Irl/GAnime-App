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
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['id'] == null || j['name'] == null) {
      throw Exception('Not a valid addon manifest (missing id/name)');
    }
    final resRaw = (j['resources'] as List?) ?? [];
    final resources = resRaw
        .map((e) => e is Map ? '${e['name'] ?? ''}' : '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    // Manifest "types" live on their own field (NOT folded into
    // resources): they decide the /stream/<type>/ path per addon.
    final types =
        ((j['types'] as List?) ?? []).map((e) => '$e').toList();
    // idPrefixes come from the resource entries, e.g. Torrentio's
    // {"name":"stream","types":["movie","series"],"idPrefixes":["tt"]}.
    final prefixSet = <String>{};
    for (final e in resRaw) {
      if (e is Map) {
        for (final p in ((e['idPrefixes'] as List?) ?? [])) {
          final s = '$p';
          if (s.isNotEmpty) prefixSet.add(s);
        }
      }
    }
    // Website parity: an addon declares configurability in behaviorHints
    // (configurationRequired is the documented flag; some use
    // configurable). Only those addons get a Configure button.
    final bh = (j['behaviorHints'] as Map<String, dynamic>?) ?? {};
    final configurable = bh['configurationRequired'] == true ||
        bh['configurable'] == true;
    return AddonRecord(
      manifestUrl: url,
      baseUrl: baseOf(url),
      id: '${j['id']}',
      name: '${j['name']}',
      version: (j['version'] as String?) ?? '',
      addedAt: DateTime.now(),
      enabled: true,
      description: (j['description'] as String?) ?? '',
      logoUrl: (j['logo'] as String?) ?? '',
      resources: resources,
      types: types,
      idPrefixes: prefixSet.toList(),
      configurable: configurable,
    );
  }

  /// Stremio `/stream/<type>/` path for one addon (website parity):
  /// movies always "movie"; anime-only addons (types has "anime" but not
  /// "series") want "anime"; every general addon wants "series".
  /// The app used to hardcode "anime" here, which 404s on general
  /// addons (they serve movie/series) — the "no streams" bug even with
  /// the addon installed and enabled.
  static String streamTypeFor(AddonRecord addon, bool isMovie) {
    if (isMovie) return 'movie';
    final t = addon.types.map((e) => e.toLowerCase()).toSet();
    if (t.contains('anime') && !t.contains('series')) return 'anime';
    return 'series';
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
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
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
