// Addon ID resolution — website parity (js/app.js resolveAddonIds +
// streamIdsFor). Stremio addons speak different id dialects: some want
// kitsu:, some anilist:, some mal:, and general ones (e.g. Torrentio)
// only understand IMDb tt: ids. The app used to query every addon with
// a single anilist: id, so tt-only addons always returned nothing.
// This resolves every id form, then builds per-addon candidates.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'kitsu.dart';

/// All id forms known for one title.
class AddonIds {
  final String? kitsu;
  final String? tt; // imdb id, tt1234567
  final int? mal;
  final int? anilist;
  final int? season; // ani.zip season number for episode 1
  final int? epOffset; // absolute-episode offset for long runners
  const AddonIds({
    this.kitsu,
    this.tt,
    this.mal,
    this.anilist,
    this.season,
    this.epOffset,
  });

  bool get isEmpty =>
      kitsu == null && tt == null && mal == null && anilist == null;
}

class AddonIdResolver {
  static final Map<int, AddonIds> _cache = {};

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolve every id form for [a]. Catalogue ids are Kitsu ids, so the
  /// kitsu: form is always known; the rest come from ani.zip / Jikan.
  /// Never throws; returns partial ids when some sources are down.
  static Future<AddonIds> resolve(Anime a) async {
    if (_cache.containsKey(a.id)) return _cache[a.id]!;
    final kitsu = '${a.id}';
    String? tt;
    int? mal = a.malId;
    int? anilist;
    int? season;
    int? epOffset;

    // 0) AniList id via the app's existing Kitsu mapping helper.
    // If a.id is a Kitsu ID, this resolves to AniList.
    // If a.id is ALREADY an AniList ID (Calendar, Tracker), this fails —
    // so fall back to using a.id directly as the AniList ID.
    try {
      anilist = await Kitsu.resolveAnilistId(a.id);
    } catch (_) {}
    // Fallback: assume a.id is an AniList ID (e.g., from Calendar).
    // The ani.zip query below will validate it — if it's wrong, no
    // mappings will be found and we'll use the original kitsu value.
    anilist ??= a.id;

    // 1) ani.zip: anilist id -> kitsu / imdb / mal + season info.
    // (Also backfills the kitsu id when the catalogue id is stale.)
    {
      final j = await _getJson(
          'https://api.ani.zip/mappings?anilist_id=$anilist');
      final m = (j?['mappings'] as Map?)?.cast<String, dynamic>();
      if (m != null) {
        final k = m['kitsu_id'];
        final imdb = '${m['imdb_id'] ?? ''}';
        if (RegExp(r'^tt\d+$').hasMatch(imdb)) tt = imdb;
        final ml = m['mal_id'];
        if (ml != null && mal == null) mal = int.tryParse('$ml');
        final ep1 =
            ((j?['episodes'] as Map?)?.cast<String, dynamic>())?['1']
                as Map?;
        if (ep1 != null) {
          final sn = ep1['seasonNumber'];
          if (sn is num && sn > 0) season = sn.toInt();
          final abs = ep1['absoluteEpisodeNumber'];
          if (abs is num && abs > 1) epOffset = abs.toInt() - 1;
        }
        if (k != null && '$k' != kitsu) {
          // Catalogue id was stale — prefer ani.zip's mapping.
          return _finish(a, '$k', tt, mal, anilist, season, epOffset);
        }
      }
    }

    // 2) IMDb via Jikan (MAL's external links).
    if (mal != null && tt == null) {
      final j = await _getJson(
          'https://api.jikan.moe/v4/anime/$mal/external');
      final data = (j?['data'] as List?) ?? [];
      for (final e in data) {
        final m = e as Map;
        if (RegExp(r'imdb', caseSensitive: false)
            .hasMatch('${m['name'] ?? ''}')) {
          final mt =
              RegExp(r'tt\d+').firstMatch('${m['url'] ?? ''}');
          if (mt != null) {
            tt = mt.group(0);
            break;
          }
        }
      }
    }

    return _finish(a, kitsu, tt, mal, anilist, season, epOffset);
  }

  static AddonIds _finish(Anime a, String kitsu, String? tt, int? mal,
      int? anilist, int? season, int? epOffset) {
    final ids = AddonIds(
      kitsu: kitsu,
      tt: tt,
      mal: mal,
      anilist: anilist,
      season: season,
      epOffset: epOffset,
    );
    // Never cache a total miss — it proves nothing and would shadow
    // a later retry (website parity).
    if (!ids.isEmpty) _cache[a.id] = ids;
    return ids;
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
        prefixes.isEmpty || prefixes.any((x) => x.startsWith(p));
    final ep = episode < 1 ? 1 : episode;
    final out = <String>[];
    // ani.zip's measured season beats the title guess (a "Part 2" cour
    // is still IMDb season 1 — reached via the absolute candidate).
    final sMatch = RegExp(
            r'season\s*(\d+)|(\d+)\s*(?:nd|rd|th)\s*season',
            caseSensitive: false)
        .firstMatch(title);
    final titleSeason = sMatch != null
        ? (int.tryParse(sMatch.group(1) ?? sMatch.group(2) ?? '') ?? 1)
        : 1;
    final seasonNum = ids.season ?? titleSeason;
    // Kitsu first: season-exact for anime.
    if (ids.kitsu != null && wants('kitsu')) {
      out.add(isMovie ? 'kitsu:${ids.kitsu}' : 'kitsu:${ids.kitsu}:$ep');
    }
    if (ids.tt != null && wants('tt')) {
      if (isMovie) {
        out.add(ids.tt!);
      } else {
        out.add('${ids.tt}:$seasonNum:$ep');
        // Long-running series are often indexed by absolute episode
        // under season 1 (ani.zip measured the offset).
        if ((ids.epOffset ?? 0) > 0) {
          out.add('${ids.tt}:1:${ids.epOffset! + ep}');
        }
      }
    }
    if (ids.anilist != null && wants('anilist')) {
      out.add(isMovie
          ? 'anilist:${ids.anilist}'
          : 'anilist:${ids.anilist}:$ep');
    }
    if (ids.mal != null && wants('mal')) {
      out.add(isMovie ? 'mal:${ids.mal}' : 'mal:${ids.mal}:$ep');
    }
    return out;
  }
}
