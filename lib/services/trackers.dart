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
import 'anilist.dart';

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
    for (final item in (j['anime'] as List?) ?? []) {
      final m = item as Map<String, dynamic>;
      final show = m['show'] as Map<String, dynamic>? ?? {};
      final ids = m['ids'] as Map<String, dynamic>? ?? {};
      final status = (m['status'] as String?) ?? 'watching';
      // Simkl poster URL (website parity: simklPosterUrl in anilist.js).
      final cover = _simklPosterUrl((show['poster'] as String?) ?? '');
      // AniList ID: check both show.ids and item-level ids (Simkl varies).
      final showIds = show['ids'] as Map<String, dynamic>?;
      final anilistId = (showIds?['anilist'] as num?)?.toInt() ??
          (ids['anilist'] as num?)?.toInt();
      out.add(LibraryEntry(
        key: 'simkl_${ids['simkl'] ?? ids['simkl_id'] ?? ''}',
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
        progress: (m['watched_episodes'] as num?)?.toInt() ?? 0,
        total: (show['total_episodes'] as num?)?.toInt(),
        score: (m['rating'] as num?)?.toDouble(),
        updatedAt: _ts(m['last_watched_at']) ~/ 1000,
      ));
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
        progress: (ls['num_watched_episodes'] as num?)?.toInt() ?? 0,
        total: (anime['num_episodes'] as num?)?.toInt(),
        score: (ls['score'] as num?)?.toDouble(),
        updatedAt: _ts(ls['updated_at']) ~/ 1000,
      ));
    }
    return out;
  }
}
