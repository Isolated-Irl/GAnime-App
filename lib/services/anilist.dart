// AniList GraphQL — public metadata catalogue only. No key needed.
// Mirrors the web app's queries (trending, popular, search, details,
// airing schedule, viewer lists, and progress pushes).
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

const _endpoint = 'https://graphql.anilist.co';
const _fields = '''
id idMal title { romaji english userPreferred }
coverImage { large medium } bannerImage description format status
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
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['errors'] != null) {
      final errs = j['errors'] as List;
      throw Exception('AniList: ${errs.isNotEmpty ? errs.first['message'] : 'query error'}');
    }
    return (j['data'] as Map<String, dynamic>?) ?? {};
  }

  static Future<List<Anime>> _page(
    Map<String, dynamic> vars,
    String sort,
  ) async {
    const q = '''
query (\$page: Int, \$perPage: Int, \$search: String, \$sort: [MediaSort]) {
  Page(page: \$page, perPage: \$perPage) {
    media(type: ANIME, search: \$search, sort: \$sort) { $_fields }
  }
}''';
    final data = await _post(q, {
      'page': 1,
      'perPage': 20,
      'sort': [sort],
      if (vars['search'] != null) 'search': vars['search'],
    });
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

  static Future<Anime> details(int id) async {
    const q = 'query (\$id: Int) { Media(id: \$id, type: ANIME) { $_fields } }';
    final data = await _post(q, {'id': id});
    return Anime.fromJson(data['Media'] as Map<String, dynamic>);
  }

  /// Airing schedule for the next 7 days, as (weekday, anime) pairs.
  static Future<List<Anime>> airing() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const q = '''
query (\$from: Int, \$to: Int) {
  Page(page: 1, perPage: 50) {
    airingSchedules(airingAt_greater: \$from, airingAt_lesser: \$to, sort: TIME) {
      airingAt episode media { $_fields }
    }
  }
}''';
    final data = await _post(q, {'from': now, 'to': now + 7 * 86400});
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
    }).toList();
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
