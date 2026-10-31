// Episode data: fetched from ani.zip (same source as the website).
// ani.zip provides episode titles, stills, air dates, runtimes, and
// overviews keyed by AniList ID — no auth required.
// Falls back to a numbered list if ani.zip is unreachable.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class EpisodesService {
  // In-memory cache: anilistId -> List<EpisodeInfo>
  static final Map<int, List<EpisodeInfo>> _cache = {};

  static Future<List<EpisodeInfo>> forAnime(Anime a) async {
    final alId = a.anilistId ?? a.id;
    if (_cache.containsKey(alId) && _cache[alId]!.isNotEmpty) {
      return _cache[alId]!;
    }

    List<EpisodeInfo> eps = [];

    // 1. Try ani.zip (website parity — no auth needed)
    if (alId > 0) {
      try {
        eps = await _fetchFromAnizip(alId);
      } catch (_) {}
    }

    // 2. Fallback: numbered list from AniList episode total
    if (eps.isEmpty) {
      var total = a.episodes ?? 0;
      if (total <= 0 && (a.nextEpisode ?? 0) > 0) {
        total = a.nextEpisode!;
      }
      if (total > 0) {
        eps = List.generate(
          total,
          (i) => EpisodeInfo(
            number: i + 1,
            title: 'Episode ${i + 1}',
            still: i < a.episodeThumbs.length ? a.episodeThumbs[i] : '',
          ),
        );
      }
    }

    if (eps.isNotEmpty) {
      _cache[alId] = eps;
    }
    return eps;
  }

  static Future<List<EpisodeInfo>> _fetchFromAnizip(int anilistId) async {
    final r = await http.get(
      Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId'),
      headers: {'Accept': 'application/json'},
    );
    if (r.statusCode != 200) return [];
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final raw = (j['episodes'] as Map<String, dynamic>?) ?? {};
    final out = <EpisodeInfo>[];
    for (final k in raw.keys) {
      if (!RegExp(r'^\d+$').hasMatch(k)) continue;
      final e = raw[k] as Map<String, dynamic>? ?? {};
      final n = (e['episodeNumber'] as num?)?.toInt() ?? int.tryParse(k) ?? 0;
      if (n < 1) continue;
      final titleMap = e['title'] as Map<String, dynamic>?;
      final title = (titleMap?['en'] as String?)?.isNotEmpty == true
          ? titleMap!['en'] as String
          : (titleMap?['ja'] as String? ?? '');
      out.add(EpisodeInfo(
        number: n,
        title: title.isNotEmpty ? title : 'Episode $n',
        still: (e['image'] as String?) ?? '',
        overview: (e['overview'] as String?) ?? '',
        runtime: (e['runtime'] as num?)?.toInt(),
        airdate: (e['airDate'] as String?) ?? '',
      ));
    }
    out.sort((x, y) => x.number.compareTo(y.number));
    return out;
  }

  /// Clear the in-memory cache (e.g. on profile switch).
  static void clearCache() => _cache.clear();
}
