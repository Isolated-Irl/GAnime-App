// Episode data: fetched from ani.zip (same source as the website).
// ani.zip provides episode titles, stills, air dates, runtimes, and
// overviews keyed by AniList ID — no auth required.
// Falls back to (and backfills from) AniList episode / nextAiringEpisode counts
// if ani.zip is unreachable or behind on airing shows.
import 'dart:convert';
import 'dart:math' as math;
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

    // Determine how many episodes should exist / have aired so far.
    // - If `nextEpisode` is present (currently airing), `nextEpisode - 1`
    //   episodes have already aired.
    // - Otherwise use `a.episodes` (total episodes for finished shows)
    //   or `a.episodeThumbs.length` (from AniList streamingEpisodes).
    final int? airedSoFar =
        (a.nextEpisode != null && a.nextEpisode! > 1) ? a.nextEpisode! - 1 : null;
    final int targetCount = airedSoFar ??
        ((a.episodes != null && a.episodes! > 0)
            ? a.episodes!
            : a.episodeThumbs.length);

    List<EpisodeInfo> eps = [];

    // 1. Try ani.zip (website parity — no auth needed)
    if (alId > 0) {
      try {
        eps = await _fetchFromAnizip(alId, maxAired: airedSoFar);
      } catch (_) {}
    }

    // 2. Backfill / Fallback:
    // If ani.zip returned nothing OR returned fewer episodes than have
    // already aired (common on new seasonal anime where TVDB/ani.zip
    // lags behind), fill in the missing episode slots up to targetCount.
    if (targetCount > 0 && eps.length < targetCount) {
      final byNum = <int, EpisodeInfo>{for (final e in eps) e.number: e};
      final maxEp = math.max(
        targetCount,
        eps.isEmpty ? 0 : eps.map((e) => e.number).reduce(math.max),
      );
      final merged = <EpisodeInfo>[];
      for (var n = 1; n <= maxEp; n++) {
        if (byNum.containsKey(n)) {
          merged.add(byNum[n]!);
        } else {
          merged.add(
            EpisodeInfo(
              number: n,
              title: 'Episode $n',
              still: (n - 1) < a.episodeThumbs.length
                  ? a.episodeThumbs[n - 1]
                  : '',
            ),
          );
        }
      }
      eps = merged;
    }

    // 3. Last-resort fallback for movies or 1-episode specials where
    // AniList has episodes == null and ani.zip is empty.
    if (eps.isEmpty &&
        (a.format.toUpperCase() == 'MOVIE' ||
            a.format.toUpperCase() == 'SPECIAL' ||
            a.format.toUpperCase() == 'OVA' ||
            a.format.toUpperCase() == 'ONA' ||
            a.status.toUpperCase() == 'FINISHED' ||
            a.status.toUpperCase() == 'RELEASING')) {
      final count = (a.nextEpisode != null && a.nextEpisode! > 1)
          ? a.nextEpisode! - 1
          : 1;
      eps = List.generate(
        count,
        (i) => EpisodeInfo(
          number: i + 1,
          title: 'Episode ${i + 1}',
          still: i < a.episodeThumbs.length ? a.episodeThumbs[i] : '',
        ),
      );
    }

    if (eps.isNotEmpty) {
      _cache[alId] = eps;
    }
    return eps;
  }

  static Future<List<EpisodeInfo>> _fetchFromAnizip(
    int anilistId, {
    int? maxAired,
  }) async {
    final r = await http
        .get(
          Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId'),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final raw = (j['episodes'] as Map<String, dynamic>?) ?? {};
    final out = <EpisodeInfo>[];
    for (final k in raw.keys) {
      if (!RegExp(r'^\d+$').hasMatch(k)) continue;
      final e = raw[k] as Map<String, dynamic>? ?? {};
      final n = (e['episodeNumber'] as num?)?.toInt() ?? int.tryParse(k) ?? 0;
      if (n < 1) continue;
      // If AniList tells us only `maxAired` episodes have aired so far,
      // don't list future unaired placeholder episodes from TVDB.
      if (maxAired != null && n > maxAired) continue;
      final titleMap = e['title'] as Map<String, dynamic>?;
      final title = (titleMap?['en'] as String?)?.isNotEmpty == true
          ? titleMap!['en'] as String
          : ((titleMap?['x-jat'] as String?)?.isNotEmpty == true
              ? titleMap!['x-jat'] as String
              : (titleMap?['ja'] as String? ?? ''));
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
