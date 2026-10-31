// Tracker connections. Tokens live ONLY on-device (SharedPreferences),
// never in the repo and never synced to Firestore.
// AniList: PIN flow (anilist.co/api/v2/oauth/pin) — the user pastes the
// 1-year token shown there. No redirect URI registration is needed.
// Simkl: PIN flow (api.simkl.com/oauth/pin) with client id + user code.
// MAL: public list via api.myanimelist.net with a user-supplied client id
// (read-only; marking never pushes to MAL, matching the web app).
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../store.dart';
import 'anilist.dart';
import 'oauth.dart';

class Trackers {
  // ---- AniList ----
  static Future<Map<String, dynamic>> anilistViewer(String token) =>
      AniList.viewer(token);
  static Future<List<LibraryEntry>> anilistLists(
          String token, int userId) =>
      AniList.userLists(token, userId);
  static Future<void> anilistSave(
          String token, int mediaId, int progress) =>
      AniList.saveProgress(token, mediaId, progress);

  static Map<String, int?>? _fuzzy(DateTime? d) =>
      d == null ? null : {'year': d.year, 'month': d.month, 'day': d.day};

  /// Full AniList entry write: status, progress, score, start/end dates.
  /// App status codes (CURRENT/COMPLETED/PLANNING/PAUSED/DROPPED) map
  /// 1:1 onto AniList's MediaListStatus enum.
  static Future<void> anilistSaveFull(
    String token,
    int mediaId, {
    int? progress,
    String? status,
    double? score,
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      AniList.saveEntry(token, mediaId,
          progress: progress,
          status: status,
          score: score,
          startedAt: _fuzzy(startDate),
          completedAt: _fuzzy(endDate));

  static Future<void> anilistDeleteEntry(String token, int mediaId) =>
      AniList.deleteEntry(token, mediaId);

  // ---- Simkl ----
  static Future<Map<String, dynamic>> simklStartPin(String clientId) async {
    final r = await http.post(
      Uri.parse('https://api.simkl.com/oauth/pin?client_id=$clientId'),
    );
    if (r.statusCode != 200) throw Exception('Simkl PIN failed: ${r.body}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> simklCheckPin(
      String clientId, String userCode) async {
    final r = await http.get(Uri.parse(
        'https://api.simkl.com/oauth/pin/$userCode?client_id=$clientId'));
    if (r.statusCode != 200) throw Exception('Simkl PIN not ready');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Simkl poster URL builder (website parity: simklPosterUrl).
  /// Handles full URLs, protocol-relative, and bare poster paths.
  /// Simkl watched count: handles watched_episodes_count (int),
  /// watched_episodes (int or List of episodes when extended).
  static int _simklProgress(Map<String, dynamic> m) {
    if (m['watched_episodes_count'] != null) {
      return _n(m['watched_episodes_count']);
    }
    final w = m['watched_episodes'];
    if (w is List) return w.length;
    return _n(w);
  }

  static String _simklPosterUrl(String poster) {
    final p = poster.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('//')) return 'https:$p';
    final hasSizeSuffix =
        RegExp(r'_(m|c|ca|cm|s|w)(\.webp|\.jpg|\.jpeg|\.png)?\$').hasMatch(p);
    if (p.contains('simkl.in/')) {
      final path = p.replaceFirst(RegExp(r'^https?://'), '');
      if (hasSizeSuffix) return 'https://$path';
      return 'https://${path.replaceFirst(RegExp(r'\.(webp|jpg|jpeg|png)\$'), '')}_m.webp';
    }
    final bare = p
        .replaceFirst(RegExp(r'_(m|c|ca|cm|s|w)(\.webp|\.jpg|\.jpeg|\.png)?\$'), '')
        .replaceFirst(RegExp(r'\.(webp|jpg|jpeg|png)\$'), '');
    if (bare.startsWith('posters/')) return 'https://simkl.in/${bare}_m.webp';
    if (bare.contains('/')) return 'https://simkl.in/posters/${bare}_m.webp';
    return 'https://simkl.in/posters/${bare.length >= 2 ? bare.substring(0, 2) : bare}/${bare}_m.webp';
  }

  /// Safe number parsing: APIs sometimes return numbers as strings.
  /// Never crashes on String-vs-num mismatches.
  static int _n(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
  static int? _optInt(dynamic v) {
    if (v == null) return null;
    final x = v is num ? v.toInt() : int.tryParse(v.toString());
    return (x == null || x <= 0) ? null : x;
  }
  static double? _optDouble(dynamic v) => v == null
      ? null
      : (v is num ? v.toDouble() : double.tryParse(v.toString()));

  /// Timestamp normalizer: Simkl returns ISO strings, AniList returns epoch numbers.
  static int _ts(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  static Future<List<LibraryEntry>> simklLists(
      String clientId, String token) async {
    final r = await http.get(
      Uri.parse('https://api.simkl.com/sync/all-items/anime?extended=full'),
      headers: {
        'Authorization': 'Bearer $token',
        'simkl-api-key': clientId,
      },
    );
    if (r.statusCode != 200) throw Exception('Simkl lists failed');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final out = <LibraryEntry>[];
    final trackerStore = await Store.tracker();
    bool trackerDirty = false;
    for (final item in (j['anime'] as List?) ?? []) {
      final m = item as Map<String, dynamic>;
      final show = m['show'] as Map<String, dynamic>? ?? {};
      final ids = m['ids'] as Map<String, dynamic>? ?? {};
      final status = (m['status'] as String?) ?? 'watching';
      // Simkl poster URL (website parity: simklPosterUrl in anilist.js).
      final cover = _simklPosterUrl((show['poster'] as String?) ?? '');
      // AniList ID: check both show.ids and item-level ids (Simkl varies).
      final showIds = show['ids'] as Map<String, dynamic>?;
      final anilistId =
          _optInt(showIds?['anilist']) ?? _optInt(ids['anilist']);
      final simklId =
          _optInt(ids['simkl']) ?? _optInt(ids['simkl_id']) ?? _optInt(showIds?['simkl']);
      // Persist Simkl ID mapping so watch pushes work
      if (anilistId != null && simklId != null) {
        trackerStore['simklIdFor_$anilistId'] = simklId;
        trackerDirty = true;
      }
      out.add(LibraryEntry(
        key: 'simkl_${simklId ?? ''}',
        source: 'simkl',
        anilistId: anilistId,
        title: (show['title'] as String?) ?? '',
        cover: cover,
        status: status == 'watching'
            ? 'CURRENT'
            : status == 'completed'
                ? 'COMPLETED'
                : status == 'plantowatch'
                    ? 'PLANNING'
                    : 'CURRENT',
        progress: _simklProgress(m),
        total: _optInt(show['total_episodes_count']) ??
            _optInt(show['total_episodes']) ??
            _optInt(m['total_episodes_count']),
        score: _optDouble(m['rating']),
        updatedAt: _ts(m['last_watched_at']) ~/ 1000,
      ));
    }
    if (trackerDirty) {
      await Store.saveTracker(trackerStore);
    }
    return out;
  }

  static Future<void> simklSave(
      String clientId, String token, int simklId, int progress) async {
    // Simkl "mark as watched" via /sync/history with the show id.
    final r = await http.post(
      Uri.parse('https://api.simkl.com/sync/history'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'simkl-api-key': clientId,
      },
      body: jsonEncode({
        'shows': [
          {
            'ids': {'simkl': simklId},
            'watched_episodes': progress,
          }
        ],
      }),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Simkl save failed: ${r.body}');
    }
  }

  static const _simklStatusMap = {
    'CURRENT': 'watching',
    'COMPLETED': 'completed',
    'PLANNING': 'plantowatch',
    'PAUSED': 'hold',
    'DROPPED': 'dropped',
    'REPEATING': 'watching',
  };

  static Map<String, String> _simklHeaders(String clientId, String token) =>
      {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'simkl-api-key': clientId,
      };

  /// Full Simkl write (website parity): status + watched episodes + memo
  /// in ONE /sync/history call. Episodes use the seasons-array format.
  static Future<void> simklSaveFull(
    String clientId,
    String token, {
    int? simklId,
    int? anilistId,
    int? malId,
    String? title,
    int? progress,
    String? status,
    String? memo,
  }) async {
    final ids = <String, dynamic>{};
    if (simklId != null) ids['simkl'] = simklId;
    if (anilistId != null) ids['anilist'] = anilistId;
    if (malId != null) ids['mal'] = malId;
    final show = <String, dynamic>{'ids': ids};
    if (title != null && title.isNotEmpty) show['title'] = title;
    if (status != null) show['status'] = _simklStatusMap[status] ?? 'watching';
    if (memo != null && memo.isNotEmpty) show['memo'] = memo;
    if (progress != null && progress > 0) {
      show['seasons'] = [
        {
          'number': 1,
          'episodes': List.generate(progress, (i) => {'number': i + 1}),
        }
      ];
    }
    if (show.length <= 1) return; // ids only — nothing to send
    final r = await http.post(
      Uri.parse('https://api.simkl.com/sync/history'),
      headers: _simklHeaders(clientId, token),
      body: jsonEncode({
        'shows': [show]
      }),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Simkl save failed: ${r.body}');
    }
  }

  /// Remove a title from the Simkl list.
  static Future<void> simklDeleteEntry(
      String clientId, String token, int simklId) async {
    final r = await http.post(
      Uri.parse('https://api.simkl.com/sync/history/remove'),
      headers: _simklHeaders(clientId, token),
      body: jsonEncode({
        'shows': [
          {
            'ids': {'simkl': simklId}
          }
        ]
      }),
    );
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 404) {
      throw Exception('Simkl delete failed: ${r.body}');
    }
  }

  // ---- MAL (read-only public list) ----
  static Future<List<LibraryEntry>> malLists(
      String username, String clientId) async {
    final r = await http.get(
      Uri.parse(
          'https://api.myanimelist.net/v2/users/$username/animelist?limit=1000&fields=list_status,num_episodes,mean'),
      headers: {'X-MAL-CLIENT-ID': clientId},
    );
    if (r.statusCode != 200) throw Exception('MAL list failed: ${r.body}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final out = <LibraryEntry>[];
    for (final node in (j['data'] as List?) ?? []) {
      final m = node as Map<String, dynamic>;
      final anime = m['node'] as Map<String, dynamic>? ?? {};
      final ls = m['list_status'] as Map<String, dynamic>? ?? {};
      final status = (ls['status'] as String?) ?? 'watching';
      out.add(LibraryEntry(
        key: 'mal_${anime['id']}',
        source: 'mal',
        title: (anime['title'] as String?) ?? '',
        cover: ((anime['main_picture'] as Map?)?['medium'] as String?) ?? '',
        status: status == 'watching'
            ? 'CURRENT'
            : status == 'completed'
                ? 'COMPLETED'
                : status == 'plan_to_watch'
                    ? 'PLANNING'
                    : 'CURRENT',
        // MAL API v2 returns 'num_episodes_watched', not 'num_watched_episodes'
        progress: _n(ls['num_episodes_watched'] ?? ls['num_watched_episodes']),
        total: _optInt(anime['num_episodes']),
        score: _optDouble(ls['score']),
        updatedAt: _ts(ls['updated_at']) ~/ 1000,
      ));
    }
    return out;
  }

  // ---- MAL writes ----
  // Status/episodes/score ride the existing relay contract
  // (POST /mal/update); dates + delete go direct (native has no CORS).
  static const _malStatusMap = {
    'CURRENT': 'watching',
    'COMPLETED': 'completed',
    'PLANNING': 'plan_to_watch',
    'PAUSED': 'on_hold',
    'DROPPED': 'dropped',
    'REPEATING': 'watching',
  };

  static Future<void> malSave(
    String accessToken,
    int malId, {
    String? status,
    int? episodes,
    double? score,
  }) async {
    final body = <String, dynamic>{
      'access_token': accessToken,
      'anime_id': malId,
    };
    if (status != null) body['status'] = _malStatusMap[status] ?? 'watching';
    if (episodes != null) body['num_watched_episodes'] = episodes;
    if (score != null) body['score'] = score.round().clamp(1, 10);
    final r = await http.post(
      Uri.parse('${OAuthService.relayUrl}/mal/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) {
      throw Exception('MAL save failed: ${r.body}');
    }
  }

  static String _malDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// MAL start/finish dates (undocumented fields, accepted by the API).
  static Future<void> malUpdateDates(
    String accessToken,
    int malId, {
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    final form = <String, String>{};
    if (startDate != null) form['start_date'] = _malDate(startDate);
    if (finishDate != null) form['finish_date'] = _malDate(finishDate);
    if (form.isEmpty) return;
    final r = await http.put(
      Uri.parse('https://api.myanimelist.net/v2/anime/$malId/my_list_status'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&'),
    );
    if (r.statusCode != 200) {
      throw Exception('MAL dates failed: ${r.body}');
    }
  }

  static Future<void> malDeleteEntry(String accessToken, int malId) async {
    final r = await http.delete(
      Uri.parse('https://api.myanimelist.net/v2/anime/$malId/my_list_status'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (r.statusCode != 200 && r.statusCode != 404) {
      throw Exception('MAL delete failed: ${r.body}');
    }
  }
}
