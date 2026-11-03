// Addon ID resolution — website parity (js/app.js resolveAddonIds +
// streamIdsFor). Stremio addons speak different id dialects: some want
// kitsu:, some anilist:, some mal:, and general ones (e.g. Torrentio)
// only understand IMDb tt: ids.
// This resolves every id form, then builds per-addon candidates.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// All id forms known for one title.
class AddonIds {
  final String? kitsu;
  final String? tt; // imdb id, tt1234567
  final int? mal;
  final int? anilist;
  final int? season; // ani.zip season number for episode 1
  final int? epOffset; // absolute-episode offset for long runners
  // Per-episode mapping from ani.zip: episodeNumber -> (seasonNumber, tvdbEpNumber, absEpNumber)
  final Map<int, ({int? season, int? epNum, int? absEp})> episodeMap;

  const AddonIds({
    this.kitsu,
    this.tt,
    this.mal,
    this.anilist,
    this.season,
    this.epOffset,
    this.episodeMap = const {},
  });

  bool get isEmpty =>
      kitsu == null && tt == null && mal == null && anilist == null;
}

class AddonIdResolver {
  static final Map<int, AddonIds> _cache = {};

  static const _headers = {
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolve every id form for [a].
  /// Catalogue ids (`a.id`) are AniList ids; kitsu, imdb, and mal ids
  /// come from ani.zip, Kitsu mappings, and Jikan.
  /// Never throws; returns partial ids when some sources are down.
  static Future<AddonIds> resolve(Anime a) async {
    final key = a.anilistId ?? a.id;
    if (_cache.containsKey(key)) return _cache[key]!;

    final int anilist = key;
    String? kitsu;
    String? tt;
    int? mal = a.malId;
    int? season;
    int? epOffset;
    final episodeMap = <int, ({int? season, int? epNum, int? absEp})>{};

    // 1) ani.zip: anilist id -> kitsu / imdb / mal + per-episode season/offset info.
    {
      final j = await _getJson(
          'https://api.ani.zip/mappings?anilist_id=$anilist');
      final m = (j?['mappings'] as Map?)?.cast<String, dynamic>();
      if (m != null) {
        final k = m['kitsu_id'];
        if (k != null && '$k'.trim().isNotEmpty) {
          kitsu = '$k'.trim();
        }
        final imdb = '${m['imdb_id'] ?? ''}'.trim();
        if (RegExp(r'^tt\d+$').hasMatch(imdb)) {
          tt = imdb;
        }
        final ml = m['mal_id'];
        if (ml != null && mal == null) {
          mal = int.tryParse('$ml');
        }

        final epsMap = (j?['episodes'] as Map?)?.cast<String, dynamic>();
        if (epsMap != null) {
          final ep1 = epsMap['1'] as Map?;
          if (ep1 != null) {
            final sn = ep1['seasonNumber'];
            if (sn is num && sn > 0) season = sn.toInt();
            final abs = ep1['absoluteEpisodeNumber'];
            if (abs is num && abs > 1) epOffset = abs.toInt() - 1;
          }
          // Record per-episode TVDB/IMDb season & episode numbers if provided.
          for (final entry in epsMap.entries) {
            final epKey = int.tryParse(entry.key);
            if (epKey == null || entry.value is! Map) continue;
            final em = entry.value as Map;
            final sn = (em['seasonNumber'] as num?)?.toInt();
            final en = (em['episodeNumber'] as num?)?.toInt();
            final abs = (em['absoluteEpisodeNumber'] as num?)?.toInt();
            episodeMap[epKey] = (season: sn, epNum: en, absEp: abs);
          }
        }
      }
    }

    // 2) Fallback for Kitsu ID via Kitsu's mapping API if ani.zip missed it.
    if (kitsu == null) {
      final j = await _getJson(
          'https://kitsu.io/api/edge/mappings?filter[externalSite]=anilist/anime&filter[externalId]=$anilist&include=item');
      final included = (j?['included'] as List?) ?? [];
      for (final item in included) {
        if (item is Map && item['type'] == 'anime' && item['id'] != null) {
          kitsu = '${item['id']}';
          break;
        }
      }
    }

    // 3) Fallback for IMDb ID via Jikan (MAL's external links) if ani.zip missed it.
    if (mal != null && tt == null) {
      final j = await _getJson(
          'https://api.jikan.moe/v4/anime/$mal/external');
      final data = (j?['data'] as List?) ?? [];
      for (final e in data) {
        final m = e as Map;
        if (RegExp(r'imdb', caseSensitive: false)
            .hasMatch('${m['name'] ?? ''}')) {
          final mt = RegExp(r'tt\d+').firstMatch('${m['url'] ?? ''}');
          if (mt != null) {
            tt = mt.group(0);
            break;
          }
        }
      }
    }

    return _finish(
        key, kitsu, tt, mal, anilist, season, epOffset, episodeMap);
  }

  static AddonIds _finish(
    int cacheKey,
    String? kitsu,
    String? tt,
    int? mal,
    int? anilist,
    int? season,
    int? epOffset,
    Map<int, ({int? season, int? epNum, int? absEp})> episodeMap,
  ) {
    final ids = AddonIds(
      kitsu: kitsu,
      tt: tt,
      mal: mal,
      anilist: anilist,
      season: season,
      epOffset: epOffset,
      episodeMap: episodeMap,
    );
    // Only cache when we resolved at least one external id beyond raw anilist,
    // so a transient network drop doesn't permanently hide kitsu/tt.
    if (kitsu != null || tt != null || mal != null) {
      _cache[cacheKey] = ids;
    }
    return ids;
  }

  /// Extracts a probable season number from an anime title when explicit
  /// metadata is missing or when testing alternative season numbering.
  static int parseSeasonFromTitle(String title) {
    // 1. "Season 2", "2nd Season", "S2", "Season II"
    final sMatch = RegExp(
      r'(?:season|s)\s*(\d+)|(\d+)\s*(?:nd|rd|th)\s*(?:season|cour|part)|(?:season|part|cour)\s+(ii|iii|iv|v|vi)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (sMatch != null) {
      final numStr = sMatch.group(1) ?? sMatch.group(2);
      if (numStr != null) {
        final parsed = int.tryParse(numStr);
        if (parsed != null && parsed > 0) return parsed;
      }
      final roman = sMatch.group(3)?.toUpperCase();
      if (roman != null) {
        return switch (roman) {
          'II' => 2,
          'III' => 3,
          'IV' => 4,
          'V' => 5,
          'VI' => 6,
          _ => 1,
        };
      }
    }
    // 2. Trailing Roman numerals in sequel titles (e.g. "Mob Psycho 100 II", "Overlord IV")
    final trailingRoman = RegExp(r'\s+(II|III|IV|V|VI)\s*$').firstMatch(title);
    if (trailingRoman != null) {
      return switch (trailingRoman.group(1)!) {
        'II' => 2,
        'III' => 3,
        'IV' => 4,
        'V' => 5,
        'VI' => 6,
        _ => 1,
      };
    }
    return 1;
  }

  /// All id forms this addon understands, best first (website parity).
  /// Callers query EVERY candidate and merge. CRITICAL dialect rule:
  /// IMDb ids take :season:episode, but Kitsu/AniList/MAL ids take ONLY
  /// :episode — those databases already split seasons into separate
  /// entries, so a season segment makes the id unparseable.
  static List<String> streamIdsFor(
    AddonRecord addon,
    AddonIds ids, {
    required String title,
    required bool isMovie,
    required int episode,
  }) {
    final prefixes = addon.idPrefixes;
    bool wants(String p) =>
        prefixes.isEmpty ||
        prefixes.any((x) => x.toLowerCase().startsWith(p.toLowerCase()));

    final ep = episode < 1 ? 1 : episode;
    final out = <String>[];
    void addUnique(String s) {
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }

    final titleSeason = parseSeasonFromTitle(title);
    final epMeta = ids.episodeMap[ep];
    final seasonNum =
        (epMeta?.season != null && epMeta!.season! > 0)
            ? epMeta.season!
            : (ids.season ?? titleSeason);

    // 1. Kitsu ID: season-exact for anime addons (Torrentio, Anime Kitsu, Comet, etc.)
    if (ids.kitsu != null && wants('kitsu')) {
      addUnique(isMovie ? 'kitsu:${ids.kitsu}' : 'kitsu:${ids.kitsu}:$ep');
    }

    // 2. IMDb ID (tt): requires :season:episode for series.
    if (ids.tt != null && wants('tt')) {
      if (isMovie) {
        addUnique(ids.tt!);
      } else {
        // If ani.zip gave us an explicit absolute offset while keeping season=1
        // (common for "Part 2" / split-cour shows like Spy x Family Cour 2),
        // try the offset episode in season 1 FIRST, plus standard season:ep.
        final absFromMeta = epMeta?.absEp;
        final absFromOffset =
            (ids.epOffset != null && ids.epOffset! > 0) ? ids.epOffset! + ep : null;
        final effectiveAbs = absFromMeta ?? absFromOffset;

        if (seasonNum == 1 && effectiveAbs != null && effectiveAbs != ep) {
          // Split-cour Season 1 part 2 on IMDb (e.g. tt12345:1:13)
          addUnique('${ids.tt}:1:$effectiveAbs');
        }

        // Primary season + episode
        addUnique('${ids.tt}:$seasonNum:$ep');

        // Also include absolute episode under season 1 for long-running shows
        if (effectiveAbs != null && effectiveAbs > ep) {
          addUnique('${ids.tt}:1:$effectiveAbs');
        }

        // If title explicitly indicates Season 2+ (or Part 2+) and differs from seasonNum,
        // add it as a fallback candidate in case the indexer split seasons differently.
        if (titleSeason != seasonNum) {
          addUnique('${ids.tt}:$titleSeason:$ep');
        }
      }
    }

    // 3. AniList ID
    if (ids.anilist != null && wants('anilist')) {
      addUnique(
          isMovie ? 'anilist:${ids.anilist}' : 'anilist:${ids.anilist}:$ep');
    }

    // 4. MAL ID
    if (ids.mal != null && wants('mal')) {
      addUnique(isMovie ? 'mal:${ids.mal}' : 'mal:${ids.mal}:$ep');
    }

    return out;
  }
}
