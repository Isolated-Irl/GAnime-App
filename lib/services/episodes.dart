// Episode data via api.ani.zip mappings (AniList id -> episodes).
// Falls back to a plain numbered list when ani.zip is down or has no
// episodes for the title, so Details never blocks on it.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class EpisodesService {
  static Future<List<EpisodeInfo>> forAnime(Anime a) async {
    try {
      final r = await http.get(
        Uri.parse('https://api.ani.zip/mappings?anilist_id=${a.id}'),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final eps = (j['episodes'] as Map<String, dynamic>?) ?? {};
        final keys = eps.keys
            .map((k) => int.tryParse(k) ?? 0)
            .where((n) => n > 0)
            .toList()
          ..sort();
        if (keys.isNotEmpty) {
          return keys.map((n) {
            final e = eps['$n'] as Map<String, dynamic>? ?? {};
            return EpisodeInfo(
              number: n,
              title: (e['title']?['en'] as String?) ??
                  (e['title']?['x-jat'] as String?) ??
                  '',
              still: (e['image'] as String?) ?? '',
              overview: (e['overview'] as String?) ?? '',
              runtime: (e['runtime'] as num?)?.toInt(),
            );
          }).toList();
        }
      }
    } catch (_) {
      // Fall through to the numbered fallback below.
    }
    final total = a.episodes ?? 0;
    if (total <= 0) return [];
    return List.generate(
      total,
      (i) => EpisodeInfo(number: i + 1, title: 'Episode ${i + 1}'),
    );
  }

  /// Stremio-style ids used by addons: for anime addons the id is
  /// `anilist:<id>`; series addons use the ani.zip season/episode mapping.
  /// We keep the simple anilist form first; addons that need the season
  /// form can be resolved from the ani.zip mapping's season field.
  static String streamIdFor(Anime a, int episode) =>
      'anilist:${a.id}:$episode';
}
