// AniList GraphQL — public metadata catalogue only. No key needed.
// Mirrors the web app's queries (trending, popular, search, details,
// airing schedule, viewer lists, and progress pushes).
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

const _endpoint = 'https://graphql.anilist.co';
const _fields = '''
id idMal title { romaji english userPreferred }
coverImage { extraLarge large medium } bannerImage description format status
episodes season seasonYear averageScore genres
nextAiringEpisode { episode airingAt }
studios { edges { isMain node { name } } }
streamingEpisodes { title thumbnail }
''';

class AniList {
  static Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> vars, {
    String? token,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // Website parity (anilist.js _post): retry ONCE on 429 only, honoring
    // Retry-After when present, else ~2s. Never retry 400/401/404.
    http.Response? r;
    for (var attempt = 0; attempt < 2; attempt++) {
      r = await http.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: jsonEncode({'query': query, 'variables': vars}),
      );
      if (r.statusCode != 429 || attempt == 1) break;
      final ra = int.tryParse(r.headers['retry-after'] ?? '');
      await Future.delayed(Duration(seconds: ra ?? 2));
    }
    if (r!.statusCode != 200) {
      throw Exception('AniList ${r.statusCode}: ${r.body}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['errors'] != null) {
      final errs = j['errors'] as List;
      throw Exception('AniList: ${errs.isNotEmpty ? errs.first['message'] : 'query error'}');
    }
    return (j['data'] as Map<String, dynamic>?) ?? {};
  }

  static Future<List<Anime>> _page(
    Map<String, dynamic> vars,
    String sort, {
    String? season,
    int? seasonYear,
    String? format,
    bool? isAdult,
    List<String>? genres,
    String? status,
  }) async {
    const q = '''
query (\$page: Int, \$perPage: Int, \$search: String, \$sort: [MediaSort], \$season: MediaSeason, \$seasonYear: Int, \$format: MediaFormat, \$isAdult: Boolean, \$genreIn: [String], \$status: MediaStatus) {
  Page(page: \$page, perPage: \$perPage) {
    media(type: ANIME, search: \$search, sort: \$sort, season: \$season, seasonYear: \$seasonYear, format: \$format, isAdult: \$isAdult, genre_in: \$genreIn, status: \$status) { $_fields }
  }
}''';
    final requestVars = <String, dynamic>{
      'page': 1,
      'perPage': 20,
      'sort': [sort],
    };
    if (vars['search'] != null) requestVars['search'] = vars['search'];
    if (season != null) requestVars['season'] = season;
    if (seasonYear != null) requestVars['seasonYear'] = seasonYear;
    if (format != null) requestVars['format'] = format;
    if (isAdult != null) requestVars['isAdult'] = isAdult;
    if (genres != null && genres.isNotEmpty) requestVars['genreIn'] = genres;
    if (status != null) requestVars['status'] = status;
    final data = await _post(q, requestVars);
    final page = data['Page'] as Map<String, dynamic>? ?? {};
    final media = (page['media'] as List?) ?? [];
    final out = media
        .map((e) => Anime.fromJson(e as Map<String, dynamic>))
        .toList();
    // Feed the local title pool for fuzzy rescue (ex-Kitsu parity).
    for (final a in out) {
      _titleCache[a.id] = a;
    }
    return out;
  }

  static Future<List<Anime>> trending() => _page({}, 'TRENDING_DESC');
  static Future<List<Anime>> popular() => _page({}, 'POPULARITY_DESC');
  /// Website parity: AniList.browse() — search with optional filters.
  /// sort defaults to SEARCH_MATCH with a query, POPULARITY_DESC without
  /// (SEARCH_MATCH is illegal without a search string).
  /// sort may be a single MediaSort string or a list.
  static Future<List<Anime>> search(
    String q, {
    List<String>? genres,
    int? year,
    String? season,
    String? format,
    String? status,
    dynamic sort,
  }) {
    final query = q.trim();
    String sortVal;
    if (sort is List && sort.isNotEmpty) {
      sortVal = '${sort.first}';
    } else if (sort is String && sort.isNotEmpty) {
      sortVal = sort;
    } else {
      sortVal = query.isNotEmpty ? 'SEARCH_MATCH' : 'POPULARITY_DESC';
    }
    if (query.isEmpty && sortVal == 'SEARCH_MATCH') {
      sortVal = 'POPULARITY_DESC';
    }
    return _page(
      {'search': query.isEmpty ? null : query},
      sortVal,
      genres: genres,
      seasonYear: year,
      // Website parity: year alone filters by seasonYear; the app's UI
      // only enables season when a year is picked, matching browse().
      season: (season != null && season.isNotEmpty)
          ? season.toUpperCase()
          : null,
      format: format,
      status: status,
      isAdult: false,
    );
  }

  /// Website parity: App.GENRES — the AniList genre enum used by the
  /// search filter UI.
  static Future<List<String>> genreList() async => const [
        'Action',
        'Adventure',
        'Comedy',
        'Drama',
        'Ecchi',
        'Fantasy',
        'Horror',
        'Mahou Shoujo',
        'Mecha',
        'Music',
        'Mystery',
        'Psychological',
        'Romance',
        'Sci-Fi',
        'Slice of Life',
        'Sports',
        'Supernatural',
        'Thriller',
      ];

  /// Website parity: season result counts. AniList's Page doesn't expose
  /// cheap per-season totals, so report unknown (-1) and the UI shows
  /// the season name without a count (same as a failed Kitsu fetch).
  static final Map<int, Map<String, int>> _seasonCounts = {};
  static Future<Map<String, int>> seasonCounts(int year) async {
    return _seasonCounts[year] ??= const {
      'winter': -1,
      'spring': -1,
      'summer': -1,
      'fall': -1,
    };
  }

  // ---- Local fuzzy rescue (ex-Kitsu parity) ----
  // Title pool fed by search results; used when the API returns few
  // hits for a possibly-misspelled query.

  static final Map<int, Anime> _titleCache = {};

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

  /// Current season, mirroring the web app's currentSeason().
  static ({String season, int year}) currentSeason([DateTime? now]) {
    final d = now ?? DateTime.now();
    if (d.month <= 1) return (season: 'WINTER', year: d.year);
    if (d.month <= 4) return (season: 'SPRING', year: d.year);
    if (d.month <= 7) return (season: 'SUMMER', year: d.year);
    return (season: 'FALL', year: d.year);
  }

  static ({String season, int year}) nextSeason([DateTime? now]) {
    final cur = currentSeason(now);
    const order = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    final i = order.indexOf(cur.season);
    if (i == 3) return (season: 'WINTER', year: cur.year + 1);
    return (season: order[i + 1], year: cur.year);
  }

  static Future<List<Anime>> popularThisSeason() {
    final s = currentSeason();
    return _page({}, 'POPULARITY_DESC',
        season: s.season, seasonYear: s.year, isAdult: false);
  }

  static Future<List<Anime>> upcomingNextSeason() {
    final s = nextSeason();
    return _page({}, 'POPULARITY_DESC',
        season: s.season, seasonYear: s.year, isAdult: false);
  }

  static Future<List<Anime>> topRated() =>
      _page({}, 'SCORE_DESC', isAdult: false);

  static Future<List<Anime>> topMovies() =>
      _page({}, 'SCORE_DESC', format: 'MOVIE', isAdult: false);

  static Future<Anime> details(int id) async {
    const q = 'query (\$id: Int) { Media(id: \$id, type: ANIME) { $_fields } }';
    final data = await _post(q, {'id': id});
    return Anime.fromJson(data['Media'] as Map<String, dynamic>);
  }

  /// Direct lookup by MyAnimeList ID. Returns null if AniList hasn't
  /// linked this MAL ID yet. Prefer this over title search whenever
  /// a MAL ID is available — it's exact, not a guess.
  static Future<Anime?> byMalId(int malId) async {
    const q = 'query (\$malId: Int) { Media(idMal: \$malId, type: ANIME) { $_fields } }';
    try {
      final data = await _post(q, {'malId': malId});
      final media = data['Media'];
      if (media == null) return null;
      return Anime.fromJson(media as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Airing schedule for the next 7 days, as (weekday, anime) pairs.
  /// Pass [from]/[to] (seconds since epoch) for any other week, e.g.
  /// the Calendar week selector.
  static Future<List<Anime>> airing({int? from, int? to}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final f = from ?? now;
    final t = to ?? (now + 7 * 86400);
    return airingRange(f, t);
  }

  static Future<List<Anime>> airingRange(int from, int to) async {
    // Website parity (weekSchedules): paginate up to 20 pages of 50 so
    // busy weeks don't silently drop episodes past the first 50.
    const q = '''
query (\$page: Int, \$perPage: Int, \$from: Int, \$to: Int) {
  Page(page: \$page, perPage: \$perPage) {
    airingSchedules(airingAt_greater: \$from, airingAt_lesser: \$to, sort: TIME) {
      airingAt episode media { $_fields }
    }
  }
}''';
    final out = <Anime>[];
    for (var pageNum = 1; pageNum <= 20; pageNum++) {
      final data = await _post(q,
          {'page': pageNum, 'perPage': 50, 'from': from - 1, 'to': to});
      final page = data['Page'] as Map<String, dynamic>? ?? {};
      final list = (page['airingSchedules'] as List?) ?? [];
      for (final e in list) {
        final j = e as Map<String, dynamic>;
        // Media can be null for delisted/private/adult-flagged broadcasts.
        // Skip instead of crashing the whole calendar fetch.
        final mediaRaw = j['media'] as Map<String, dynamic>?;
        if (mediaRaw == null) continue;
        // Calendar is a general-audience surface: never show adult titles.
        final genres =
            ((mediaRaw['genres'] as List?) ?? []).map((g) => '$g').toList();
        if (genres.any((g) => g.toLowerCase() == 'hentai')) continue;
        final a = Anime.fromJson(mediaRaw);
        out.add(Anime(
          id: a.id,
          title: a.title,
          cover: a.cover,
          banner: a.banner,
          bannerXL: a.bannerXL,
          description: a.description,
          format: a.format,
          status: a.status,
          episodes: a.episodes,
          nextEpisode: (j['episode'] as num?)?.toInt(),
          airingAt: (j['airingAt'] as num?)?.toInt(),
          score: a.score,
          genres: a.genres,
          malId: a.malId,
          year: a.year,
          season: a.season,
          anilistId: a.anilistId,
        ));
      }
      if (list.length < 50) break;
    }
    return out;
  }

  static Future<Map<String, dynamic>> viewer(String token) async {
    final data = await _post(
      'query { Viewer { id name avatar { large } } }',
      {},
      token: token,
    );
    return (data['Viewer'] as Map<String, dynamic>?) ?? {};
  }

  /// AniList score can come back as num or String depending on the
  /// user's score format — parse defensively.
  static int _safeInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  static double? _parseScore(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Future<List<LibraryEntry>> userLists(
      String token, int userId) async {
    const q = '''
query (\$userId: Int) {
  MediaListCollection(userId: \$userId, type: ANIME) {
    lists { entries {
      status progress score updatedAt media { $_fields }
    } }
  }
}''';
    final data = await _post(q, {'userId': userId}, token: token);
    final coll =
        data['MediaListCollection'] as Map<String, dynamic>? ?? {};
    final lists = (coll['lists'] as List?) ?? [];
    final out = <LibraryEntry>[];
    for (final l in lists) {
      for (final e in (l as Map<String, dynamic>)['entries'] as List? ?? []) {
        final j = e as Map<String, dynamic>;
        final m = Anime.fromJson(j['media'] as Map<String, dynamic>);
        out.add(LibraryEntry(
          key: 'anilist_${m.id}',
          source: 'anilist',
          title: m.title,
          cover: m.cover,
          status: (j['status'] as String?) ?? 'CURRENT',
          progress: _safeInt(j['progress']),
          total: m.episodes,
          score: _parseScore(j['score']),
          anilistId: m.id,
          updatedAt: _safeInt(j['updatedAt']),
        ));
      }
    }
    return out;
  }

  static Future<void> saveProgress(
      String token, int mediaId, int progress) async {
    const q = '''
mutation (\$mediaId: Int, \$progress: Int) {
  SaveMediaListEntry(mediaId: \$mediaId, progress: \$progress) { id progress }
}''';
    await _post(q, {'mediaId': mediaId, 'progress': progress}, token: token);
  }

  /// Full entry save: status, progress, score, start/end dates.
  /// Only non-null fields are sent (AniList updates are partial).
  static Future<void> saveEntry(
    String token,
    int mediaId, {
    int? progress,
    String? status,
    double? score,
    Map<String, int?>? startedAt,
    Map<String, int?>? completedAt,
  }) async {
    const q = '''
mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus, \$score: Float, \$startedAt: FuzzyDateInput, \$completedAt: FuzzyDateInput) {
  SaveMediaListEntry(mediaId: \$mediaId, progress: \$progress, status: \$status, score: \$score, startedAt: \$startedAt, completedAt: \$completedAt) { id progress status score }
}''';
    final vars = <String, dynamic>{'mediaId': mediaId};
    if (progress != null) vars['progress'] = progress;
    if (status != null) vars['status'] = status;
    if (score != null) vars['score'] = score;
    if (startedAt != null) vars['startedAt'] = startedAt;
    if (completedAt != null) vars['completedAt'] = completedAt;
    await _post(q, vars, token: token);
  }

  /// Delete a list entry. Takes the AniList *media* id: resolves the
  /// MediaList entry id first, then deletes it.
  static Future<void> deleteEntry(String token, int mediaId) async {
    const q = '''
query (\$mediaId: Int) {
  Media(id: \$mediaId, type: ANIME) { mediaListEntry { id } }
}''';
    final data = await _post(q, {'mediaId': mediaId}, token: token);
    final entryId =
        ((data['Media'] as Map?)?['mediaListEntry'] as Map?)?['id'] as num?;
    if (entryId == null) return; // not on the list — nothing to delete
    const dq = '''
mutation (\$id: Int) {
  DeleteMediaListEntry(id: \$id) { deleted }
}''';
    await _post(dq, {'id': entryId.toInt()}, token: token);
  }
}
