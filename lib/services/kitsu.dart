// Kitsu catalogue: Home rails, Search, Details metadata, episode lists.
// JSON:API at https://kitsu.io/api/edge. All endpoints verified live
// 2026-10-29. Calendar stays on AniList airing; tracking stays on
// AniList/Simkl/MAL; Firebase sync and user-installed addons untouched.
//
// Two Kitsu API quirks handled here:
// - The `genres` relationship is deprecated (always empty); genre-like
//   data lives in `categories`, intersected with /genres names so chips
//   show true genres (Fantasy, Drama) instead of theme tags (Elf, Shounen).
// - /trending/anime ignores `include`, so its items get categories via
//   one small per-item request each (best-effort, empty on failure).
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import 'anilist.dart'; // season helpers only (currentSeason/nextSeason)

class Kitsu {
  static const _base = 'https://kitsu.io/api/edge';
  static const _headers = {
    'Accept': 'application/vnd.api+json',
    'User-Agent': 'GAnime-Android/1.0',
  };

  static Future<Map<String, dynamic>> _get(String path) async {
    // Website parity (anilist.js _post): retry ONCE on 429 only, honoring
    // Retry-After when present, else ~2s. Never retry 400/401/404.
    // 15s timeout: Kitsu calls with wrong IDs (e.g. AniList ID passed as
    // Kitsu ID from calendar) must fail fast, not hang the details page.
    http.Response? r;
    for (var attempt = 0; attempt < 2; attempt++) {
      r = await http
          .get(Uri.parse('$_base$path'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 429 || attempt == 1) break;
      final ra = int.tryParse(r.headers['retry-after'] ?? '');
      await Future.delayed(Duration(seconds: ra ?? 2));
    }
    if (r!.statusCode != 200) throw Exception('Kitsu ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Names from /genres (cached). Used to keep only true genres out of
  /// the noisier `categories` list for chips.
  static Future<Set<String>>? _genreNamesF;
  static Future<Set<String>> _genreNames() => _genreNamesF ??= () async {
        try {
          final j = await _get('/genres?page[limit]=100');
          final data = (j['data'] as List?) ?? [];
          return data
              .map((g) => ((g as Map)['attributes'] as Map?)?['name'])
              .whereType<String>()
              .toSet();
        } catch (_) {
          return <String>{};
        }
      }();

  /// Genre names for the Search filter UI. Falls back to a short honest
  /// hardcoded list when /genres is unreachable.
  static Future<List<String>> genreList() async {
    final names = await _genreNames();
    if (names.isEmpty) {
      return const [
        'Action',
        'Adventure',
        'Comedy',
        'Drama',
        'Fantasy',
        'Horror',
        'Mystery',
        'Romance',
        'Sci-Fi',
        'Slice of Life',
        'Sports',
        'Supernatural',
        'Suspense',
      ];
    }
    final list = names.toList()..sort();
    return list;
  }

  static List<String> _cleanGenres(
      List<String> names, Set<String> genreNames) {
    if (genreNames.isEmpty) return names;
    final f = names.where(genreNames.contains).toList();
    return f.isNotEmpty ? f : names;
  }

  /// id -> category title, from the `included` array of a response that
  /// used `include=categories`.
  static Map<String, String> _categoryNames(Map<String, dynamic> j) {
    final out = <String, String>{};
    final inc = (j['included'] as List?) ?? [];
    for (final i in inc) {
      final m = i as Map<String, dynamic>;
      if (m['type'] == 'categories') {
        out['${m['id']}'] =
            ((m['attributes'] as Map?)?['title'] as String?) ?? '';
      }
    }
    return out;
  }

  static List<String> _genresOf(Map<String, dynamic> j,
      Map<String, String> catNames, Set<String> genreNames) {
    final rel =
        ((j['relationships'] as Map?)?['categories'] as Map?)?['data'] as List? ??
            [];
    final names = rel
        .map((c) => catNames['${(c as Map)['id']}'])
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    return _cleanGenres(names, genreNames);
  }

  static Anime _fromJson(Map<String, dynamic> j,
      Map<String, String> catNames, Set<String> genreNames) {
    final a = (j['attributes'] as Map?) ?? {};
    final titles = (a['titles'] as Map?) ?? {};
    final poster = (a['posterImage'] as Map?) ?? {};
    final cover = (a['coverImage'] as Map?) ?? {};
    final en = titles['en'] as String?;
    final title = (en != null && en.isNotEmpty)
        ? en
        : (a['canonicalTitle'] as String?) ?? '';
    final st = (a['status'] as String?) ?? '';
    final status = st == 'current'
        ? 'RELEASING'
        : st == 'finished'
            ? 'FINISHED'
            : (st == 'tba' || st == 'unreleased' || st == 'upcoming')
                ? 'NOT_YET_RELEASED'
                : st.toUpperCase();
    int? year;
    var season = '';
    final sd = a['startDate'] as String?;
    if (sd != null && sd.length >= 7) {
      year = int.tryParse(sd.substring(0, 4));
      final m = int.tryParse(sd.substring(5, 7)) ?? 0;
      season = m <= 1
          ? 'WINTER'
          : m <= 4
              ? 'SPRING'
              : m <= 7
                  ? 'SUMMER'
                  : 'FALL';
    }
    final rating = a['averageRating'];
    return Anime(
      id: int.tryParse('${j['id']}') ?? 0,
      title: title,
      romaji: (titles['en_jp'] as String?) ?? '',
      cover:
          (poster['large'] as String?) ?? (poster['medium'] as String?) ?? '',
      banner: (cover['large'] as String?) ?? '',
      // Full-res hero source: Kitsu coverImage.original, else the large URL.
      bannerXL: ((cover['original'] as String?)?.isNotEmpty == true
              ? cover['original'] as String?
              : null) ??
          (cover['large'] as String?) ??
          '',
      description: (a['synopsis'] as String?) ?? '',
      format: ((a['subtype'] as String?) ?? '').toUpperCase(),
      status: status,
      episodes: (a['episodeCount'] as num?)?.toInt(),
      score: rating == null ? null : double.tryParse('$rating'),
      genres: _genresOf(j, catNames, genreNames),
      year: year,
      season: season,
      trailerId: (a['youtubeVideoId'] as String?) ?? '',
    );
  }

  static Future<List<Anime>> _list(String path) async {
    final gn = await _genreNames();
    final j = await _get(path);
    final catNames = _categoryNames(j);
    final data = (j['data'] as List?) ?? [];
    final items = data
        .map((e) => _fromJson(e as Map<String, dynamic>, catNames, gn))
        .toList();
    cacheTitles(items); // feed the fuzzy title pool (website parity)
    return items;
  }

  // ---------- Fuzzy title pool + scoring (website parity) ----------
  // The website keeps a titleCache of everything it has seen and, when a
  // search returns < 5 results, runs a "misspelling rescue": retry the API
  // with the longest query word, then local Levenshtein matching against
  // the cached titles. Same here, adapted to Kitsu.

  /// Every title Kitsu has returned this session, keyed by id.
  static final Map<int, Anime> _titleCache = {};

  static void cacheTitles(List<Anime> items) {
    for (final a in items) {
      _titleCache[a.id] = a;
    }
  }

  static int _lev(String a, String b) {
    if ((a.length - b.length).abs() > 3) return 99;
    final row = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var prev = row[0];
      row[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final tmp = row[j];
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = row[j] + 1;
        final ins = row[j - 1] + 1;
        if (ins < best) best = ins;
        final sub = prev + cost;
        if (sub < best) best = sub;
        row[j] = best;
        prev = tmp;
      }
    }
    return row[b.length];
  }

  static int _fuzzyScore(String q, String title) {
    final needle = q.toLowerCase();
    final hay = title.toLowerCase();
    if (hay.contains(needle)) return 100;
    var best = 0;
    for (final word in hay.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.isEmpty) continue;
      if (needle.length >= 3 &&
          word.startsWith(needle.substring(0, 3)) &&
          best < 50) {
        best = 50;
      }
      final d = _lev(needle, word);
      if (d <= 2) {
        final s = 70 - d * 10;
        if (s > best) best = s;
      }
    }
    // subsequence check
    var i = 0;
    for (var k = 0; k < hay.length && i < needle.length; k++) {
      if (hay[k] == needle[i]) i++;
    }
    if (i == needle.length && best < 40) best = 40;
    return best;
  }

  /// Local fuzzy matches for [q], excluding [excludeIds], best first.
  static List<Anime> fuzzyLocal(String q, Set<int> excludeIds,
      [int limit = 8]) {
    final scored = <MapEntry<Anime, int>>[];
    for (final t in _titleCache.values) {
      if (excludeIds.contains(t.id)) continue;
      final s = _fuzzyScore(q, t.title);
      if (s >= 40) scored.add(MapEntry(t, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  /// Trending Now. /trending/anime returns 10 items and ignores `include`,
  /// so genres are enriched per item (best-effort).
  static Future<List<Anime>> trending() async {
    final items = await _list('/trending/anime');
    if (items.isEmpty) return items;
    final gn = await _genreNames();
    return Future.wait(items.map((a) async {
      if (a.id == 0) return a;
      try {
        final j = await _get('/anime/${a.id}/categories?page[limit]=40');
        final data = (j['data'] as List?) ?? [];
        final names = data
            .map((c) => (((c as Map)['attributes'] as Map?)?['title']))
            .whereType<String>()
            .where((n) => n.isNotEmpty)
            .toList();
        final g = _cleanGenres(names, gn);
        return g.isEmpty ? a : a.copyWith(genres: g);
      } catch (_) {
        return a;
      }
    }));
  }

  /// All Time Popular.
  static Future<List<Anime>> popular() =>
      _list('/anime?sort=-userCount&page[limit]=20&include=categories');

  /// Top 100 Anime.
  static Future<List<Anime>> topRated() =>
      _list('/anime?sort=ratingRank&page[limit]=20&include=categories');

  /// Top 100 Movies.
  static Future<List<Anime>> topMovies() => _list(
      '/anime?filter[subtype]=movie&sort=ratingRank&page[limit]=20&include=categories');

  /// Popular This Season.
  static Future<List<Anime>> popularThisSeason() {
    final s = AniList.currentSeason();
    return _list('/anime?filter[seasonYear]=${s.year}'
        '&filter[season]=${s.season.toLowerCase()}'
        '&sort=-userCount&page[limit]=20&include=categories');
  }

  /// Upcoming Next Season.
  static Future<List<Anime>> upcomingNextSeason() {
    final s = AniList.nextSeason();
    return _list('/anime?filter[seasonYear]=${s.year}'
        '&filter[season]=${s.season.toLowerCase()}'
        '&sort=-userCount&page[limit]=20&include=categories');
  }

  /// Search, with optional filters. All filter params are optional so the
  /// plain search(q) call keeps working; empty query + filters also works.
  /// When [season] is set (winter/spring/summer/fall), [year] is sent as
  /// filter[seasonYear] alongside it; otherwise year uses filter[year].
  static Future<List<Anime>> search(
    String q, {
    List<String>? genres,
    int? year,
    String? subtype,
    String? status,
    String? sort,
    String? season,
  }) {
    final p = <String>[];
    if (q.trim().isNotEmpty) {
      p.add('filter[text]=${Uri.encodeQueryComponent(q.trim())}');
    }
    if (genres != null && genres.isNotEmpty) {
      p.add('filter[genres]=${Uri.encodeQueryComponent(genres.join(','))}');
    }
    if (year != null && season != null && season.isNotEmpty) {
      p.add('filter[seasonYear]=$year');
      p.add('filter[season]=${Uri.encodeQueryComponent(season)}');
    } else if (year != null) {
      p.add('filter[year]=$year');
    }
    if (subtype != null && subtype.isNotEmpty) {
      p.add('filter[subtype]=${Uri.encodeQueryComponent(subtype)}');
    }
    if (status != null && status.isNotEmpty) {
      p.add('filter[status]=${Uri.encodeQueryComponent(status)}');
    }
    if (sort != null && sort.isNotEmpty) {
      p.add('sort=${Uri.encodeQueryComponent(sort)}');
    }
    p.add('page[limit]=20');
    p.add('include=categories');
    return _list('/anime?${p.join('&')}');
  }

  /// Season result counts for one year: {winter: N, spring: N, ...}.
  /// Cached per year. Never throws — a failed season reports -1, and the
  /// UI shows the season name without a count rather than a fake number.
  static final Map<int, Map<String, int>> _seasonCounts = {};
  static Future<Map<String, int>> seasonCounts(int year) async {
    final cached = _seasonCounts[year];
    if (cached != null) return cached;
    const seasons = ['winter', 'spring', 'summer', 'fall'];
    final results = await Future.wait(seasons.map((s) async {
      try {
        final j = await _get(
            '/anime?filter[seasonYear]=$year&filter[season]=$s&page[limit]=1');
        final c = (j['meta'] as Map?)?['count'];
        return MapEntry(s, c is num ? c.toInt() : -1);
      } catch (_) {
        return MapEntry(s, -1);
      }
    }));
    final m = {for (final e in results) e.key: e.value};
    _seasonCounts[year] = m;
    return m;
  }

  static Future<Anime> details(int id) async {
    final gn = await _genreNames();
    final j = await _get('/anime/$id?include=categories');
    final data = j['data'] as Map<String, dynamic>;
    return _fromJson(data, _categoryNames(j), gn);
  }

  /// Full episode list with pagination. Title prefers en_us/en_jp, then en.
  static Future<List<EpisodeInfo>> episodes(int kitsuId) async {
    const per = 20;
    final out = <EpisodeInfo>[];
    var offset = 0;
    var total = 1 << 30;
    while (out.length < total) {
      final j = await _get(
          '/anime/$kitsuId/episodes?page[limit]=$per&page[offset]=$offset');
      final meta = (j['meta'] as Map?)?['count'] as num?;
      if (meta != null) total = meta.toInt();
      final data = (j['data'] as List?) ?? [];
      if (data.isEmpty) break;
      for (final e in data) {
        final at = ((e as Map)['attributes'] as Map?) ?? {};
        final titles = (at['titles'] as Map?) ?? {};
        final thumb = (at['thumbnail'] as Map?) ?? {};
        out.add(EpisodeInfo(
          number: (at['number'] as num?)?.toInt() ?? 0,
          title: (titles['en_us'] as String?) ??
              (titles['en_jp'] as String?) ??
              (titles['en'] as String?) ??
              '',
          still: (thumb['original'] as String?) ?? '',
          overview: (at['synopsis'] as String?) ?? '',
          runtime: (at['length'] as num?)?.toInt(),
          airdate: (at['airdate'] as String?) ?? '',
        ));
      }
      offset += per;
      if (data.length < per) break;
    }
    out.removeWhere((e) => e.number <= 0);
    out.sort((a, b) => a.number.compareTo(b.number));
    return out;
  }

  /// Kitsu id -> AniList id, cached. Null when the title has no mapping.
  static final Map<int, int?> _anilistCache = {};
  static Future<int?> resolveAnilistId(int kitsuId) async {
    if (_anilistCache.containsKey(kitsuId)) return _anilistCache[kitsuId];
    int? al;
    try {
      final j = await _get(
          '/anime/$kitsuId/mappings?filter[externalSite]=anilist/anime');
      final data = (j['data'] as List?) ?? [];
      if (data.isNotEmpty) {
        final ext =
            (((data.first as Map)['attributes'] as Map?)?['externalId']);
        al = int.tryParse('$ext');
      }
    } catch (_) {}
    _anilistCache[kitsuId] = al;
    return al;
  }

  /// AniList id -> Kitsu anime id, via the mappings table. Null when the
  /// title has no Kitsu mapping. Never throws.
  static Future<int?> _anilistToKitsuId(int anilistId) async {
    try {
      final m = await _get(
          '/mappings?filter[externalSite]=anilist/anime&filter[externalId]=$anilistId');
      final data = (m['data'] as List?) ?? [];
      if (data.isEmpty) return null;
      final rel =
          (((data.first as Map)['relationships'] as Map?)?['item'] as Map?);
      final href = ((rel?['links'] as Map?)?['related'] as String?);
      if (href == null || href.isEmpty) return null;
      final path = href.startsWith(_base) ? href.substring(_base.length) : href;
      final item = await _get(path);
      return int.tryParse('${(item['data'] as Map?)?['id']}');
    } catch (_) {
      return null;
    }
  }

  /// AniList id -> full Kitsu Anime. Used for Calendar and tracker entries,
  /// which still carry AniList ids, so Details gets a proper Kitsu object
  /// (episodes, stream ids and tracker pushes all agree). Null when the
  /// title has no Kitsu mapping — callers fall back to the AniList object.
  static Future<Anime?> fromAnilist(int anilistId) async {
    final kid = await _anilistToKitsuId(anilistId);
    if (kid == null || kid <= 0) return null;
    try {
      return await details(kid);
    } catch (_) {
      return null;
    }
  }
}
