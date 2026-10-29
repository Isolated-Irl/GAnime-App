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
''';

class AniList {
  static Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> vars, {
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final r = await http.post(
      Uri.parse(_endpoint),
      headers: headers,
      body: jsonEncode({'query': query, 'variables': vars}),
    );
    if (r.statusCode != 200) {
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
  }) async {
    const q = '''
query (\$page: Int, \$perPage: Int, \$search: String, \$sort: [MediaSort], \$season: MediaSeason, \$seasonYear: Int, \$format: MediaFormat, \$isAdult: Boolean) {
  Page(page: \$page, perPage: \$perPage) {
    media(type: ANIME, search: \$search, sort: \$sort, season: \$season, seasonYear: \$seasonYear, format: \$format, isAdult: \$isAdult) { $_fields }
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
    final data = await _post(q, requestVars);
    final page = data['Page'] as Map<String, dynamic>? ?? {};
    final media = (page['media'] as List?) ?? [];
    return media
        .map((e) => Anime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Anime>> trending() => _page({}, 'TRENDING_DESC');
  static Future<List<Anime>> popular() => _page({}, 'POPULARITY_DESC');
  static Future<List<Anime>> search(String q) =>
      _page({'search': q}, 'SEARCH_MATCH');

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
    const q = '''
query (\$from: Int, \$to: Int) {
  Page(page: 1, perPage: 50) {
    airingSchedules(airingAt_greater: \$from, airingAt_lesser: \$to, sort: TIME) {
      airingAt episode media { $_fields }
    }
  }
}''';
    final data = await _post(q, {'from': from, 'to': to});
    final page = data['Page'] as Map<String, dynamic>? ?? {};
    final list = (page['airingSchedules'] as List?) ?? [];
    return list.map((e) {
      final j = e as Map<String, dynamic>;
      final a = Anime.fromJson(j['media'] as Map<String, dynamic>);
      return Anime(
        id: a.id,
        title: a.title,
        cover: a.cover,
        banner: a.banner,
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
      );
      // Calendar is a general-audience surface: never show adult titles.
    }).where((a) => !a.genres.any((g) => g.toLowerCase() == 'hentai')).toList();
  }

  static Future<Map<String, dynamic>> viewer(String token) async {
    final data = await _post(
      'query { Viewer { id name avatar { large } } }',
      {},
      token: token,
    );
    return (data['Viewer'] as Map<String, dynamic>?) ?? {};
  }

  static Future<List<LibraryEntry>> userLists(
      String token, int userId) async {
    const q = '''
query (\$userId: Int) {
  MediaListCollection(userId: \$userId, type: ANIME) {
    lists { entries {
      status progress score media { $_fields }
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
          progress: (j['progress'] as num?)?.toInt() ?? 0,
          total: m.episodes,
          score: (j['score'] as num?)?.toDouble(),
          anilistId: m.id,
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
}
