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

    // How many episodes have aired or exist according to AniList?
    final isReleasing = a.status.toUpperCase() == 'RELEASING';
    final int? airedSoFar = (a.nextEpisode != null && a.nextEpisode! > 1)
        ? a.nextEpisode! - 1
        : null;
    final int anilistTotal = a.episodes ?? 0;
    final int thumbsCount = a.episodeThumbs.length;

    // For currently airing shows where nextEpisode is known, cap/target
    // the aired count; otherwise use total episodes or streaming thumb count.
    int targetCount = 0;
    if (isReleasing && airedSoFar != null && airedSoFar > 0) {
      targetCount = airedSoFar;
    } else if (anilistTotal > 0) {
      targetCount = anilistTotal;
    } else if (airedSoFar != null && airedSoFar > 0) {
      targetCount = airedSoFar;
    } else if (thumbsCount > 0) {
      targetCount = thumbsCount;
    }

    if (_cache.containsKey(alId) &&
        _cache[alId]!.isNotEmpty &&
        _cache[alId]!.length >= targetCount) {
      return _cache[alId]!;
    }

    List<EpisodeInfo> eps = [];

    // 1. Try ani.zip (with a 10s timeout so a hung connection never blocks UI)
    if (alId > 0) {
      try {
        eps = await _fetchFromAnizip(alId, maxAired: airedSoFar);
      } catch (_) {}
    }

    // 2. Backfill / Fallback:
    // If ani.zip returned nothing OR returned fewer episodes than have
    // already aired (common on new seasonal anime where TVDB/ani.zip
    // lags behind), fill in every missing episode 1..maxEp.
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

    // 3. Last-resort fallback: if a show is FINISHED, RELEASING, or a MOVIE/OVA
    // and both ani.zip and AniList episode counts are null/empty, provide at
    // least Episode 1 so the user can always open the Sources screen.
    if (eps.isEmpty &&
        a.status.toUpperCase() != 'NOT_YET_RELEASED') {
      final fallbackCount = math.max(1, targetCount);
      eps = List.generate(
        fallbackCount,
        (i) => EpisodeInfo(
          number: i + 1,
          title: a.format.toUpperCase() == 'MOVIE'
              ? 'Complete Movie'
              : 'Episode ${i + 1}',
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
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);

    for (final k in raw.keys) {
      if (!RegExp(r'^\d+$').hasMatch(k)) continue;
      final e = raw[k] as Map<String, dynamic>? ?? {};
      final n = (e['episodeNumber'] as num?)?.toInt() ?? int.tryParse(k) ?? 0;
      if (n < 1) continue;
      // Filter out future unaired placeholder episodes if maxAired is known.
      if (maxAired != null && n > maxAired) continue;
      final airDate = (e['airDate'] as String?) ?? '';
      if (maxAired == null &&
          airDate.length >= 10 &&
          airDate.substring(0, 10).compareTo(todayIso) > 0) {
        continue;
      }
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
        airdate: airDate,
      ));
    }
    out.sort((x, y) => x.number.compareTo(y.number));
    return out;
  }

  /// Clear the in-memory cache (e.g. on profile switch).
  static void clearCache() => _cache.clear();
}
