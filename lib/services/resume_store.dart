// Resume-position store: remembers WHERE you stopped in every episode,
// per profile, on-device (SharedPreferences) and merged into the cloud doc.
//
// Shape: {profileId: {"animeId:ep": {"p": posMs, "d": durMs, "t": savedAtMs, "x": 1?}}}
//  - "x":1 means "finished / cleared" (kept as a tombstone so an older cloud
//    copy can't bring the spot back after you finished the episode).
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ResumeEntry {
  final int posMs, durMs, at;
  const ResumeEntry(this.posMs, this.durMs, this.at);
}

/// One "resume this episode" card for the Home screen.
class ResumeItem {
  final int animeId, ep, posMs, durMs, at;
  final String title, cover;
  final int? total; // total episodes, null when unknown (display only)
  const ResumeItem(this.animeId, this.ep, this.posMs, this.durMs, this.at,
      this.title, this.cover, [this.total]);
}

class ResumeStore {
  /// Bumps whenever a spot is saved on pause/exit or cleared, so Home can
  /// refresh its Continue Watching row. (The 5-second periodic saves do NOT
  /// bump it, to avoid pointless rebuilds while playing.)
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static const _k = 'ganime_resume';
  static const _maxPerProfile = 400;

  /// Set once by main.dart: runs the normal cloud sync (best-effort).
  static Future<void> Function()? cloudPush;
  static int _lastCloudPush = 0;

  /// Ask for a cloud sync. Throttled to once a minute unless [force].
  static void requestCloudPush({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastCloudPush < 60000) return;
    _lastCloudPush = now;
    try {
      cloudPush?.call();
    } catch (_) {}
  }

  // All reads/writes go through one queue so they can never overwrite
  // each other (same lost-update bug that broke the subtitle prefs).
  static Future<void> _q = Future<void>.value();

  static Future<T> _run<T>(Future<T> Function() task) {
    final c = _q.then((_) => task());
    _q = c.then((_) {}, onError: (_) {});
    return c;
  }

  static Future<Map<String, dynamic>> _readAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAll(Map<String, dynamic> m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(m));
  }

  static String _key(int animeId, int ep) => '$animeId:$ep';

  static Map<String, dynamic> _profile(Map<String, dynamic> all, String pid) =>
      Map<String, dynamic>.from((all[pid] as Map?) ?? {});

  /// Where to resume this episode (null = start from the beginning).
  static Future<ResumeEntry?> get(String pid, int animeId, int ep) =>
      _run(() async {
        final e = _profile(await _readAll(), pid)[_key(animeId, ep)];
        if (e is! Map || e['x'] == 1) return null;
        final p = (e['p'] as num?)?.toInt() ?? 0;
        if (p <= 0) return null;
        return ResumeEntry(p, (e['d'] as num?)?.toInt() ?? 0,
            (e['t'] as num?)?.toInt() ?? 0);
      });

  static Future<void> save(
          String pid, int animeId, int ep, int posMs, int durMs,
          {String title = '', String cover = '', int? total, bool notify = true}) =>
      _put(
          pid,
          animeId,
          ep,
          {
            'p': posMs,
            'd': durMs,
            't': DateTime.now().millisecondsSinceEpoch,
            if (title.isNotEmpty) 'ti': title,
            if (cover.isNotEmpty) 'cv': cover,
            if (total != null && total > 0) 'tt': total,
          },
          notify);

  /// Finished episode: forget the spot (tombstone so the cloud copy dies too).
  static Future<void> clear(String pid, int animeId, int ep) => _put(pid,
      animeId, ep, {'p': 0, 'd': 0, 't': DateTime.now().millisecondsSinceEpoch, 'x': 1});

  /// Remove an anime entirely from Continue Watching (all episodes).
  /// Only touches resume spots — watched checkmarks and library are untouched.
  static Future<void> clearAnime(String pid, int animeId) =>
      _run(() async {
        final all = await _readAll();
        final prof = _profile(all, pid);
        final prefix = '$animeId:';
        final toRemove = prof.keys.where((k) => k.startsWith(prefix)).toList();
        for (final k in toRemove) {
          prof.remove(k);
        }
        all[pid] = prof;
        await _writeAll(all);
        changed.value++;
      });

  static Future<void> _put(
          String pid, int animeId, int ep, Map<String, dynamic> v,
          [bool notify = true]) =>
      _run(() async {
        final all = await _readAll();
        final prof = _profile(all, pid);
        prof[_key(animeId, ep)] = v;
        if (prof.length > _maxPerProfile) {
          final keys = prof.keys.toList()
            ..sort((a, b) => ((prof[a] as Map)['t'] as num? ?? 0)
                .compareTo((prof[b] as Map)['t'] as num? ?? 0));
          for (final k in keys.take(prof.length - _maxPerProfile)) {
            prof.remove(k);
          }
        }
        all[pid] = prof;
        await _writeAll(all);
        if (notify) changed.value++;
      });

  /// Half-watched episodes for the Home "Continue watching" row: newest
  /// first, one per anime, within the last 60 days. Entries saved before
  /// titles were stored are skipped (they can't be drawn as a card).
  static Future<List<ResumeItem>> recent(String pid, {int limit = 12}) =>
      _run(() async {
        final prof = _profile(await _readAll(), pid);
        final cutoff = DateTime.now().millisecondsSinceEpoch -
            const Duration(days: 60).inMilliseconds;
        final byAnime = <int, ResumeItem>{};
        prof.forEach((k, v) {
          if (v is! Map || v['x'] == 1) return;
          final parts = k.split(':');
          if (parts.length != 2) return;
          final aid = int.tryParse(parts[0]);
          final ep = int.tryParse(parts[1]);
          final p = (v['p'] as num?)?.toInt() ?? 0;
          final d = (v['d'] as num?)?.toInt() ?? 0;
          final t = (v['t'] as num?)?.toInt() ?? 0;
          final title = (v['ti'] as String?) ?? '';
          if (aid == null || ep == null) return;
          if (p < 10000 || d <= 0 || title.isEmpty || t < cutoff) return;
          final item = ResumeItem(
              aid, ep, p, d, t, title, (v['cv'] as String?) ?? '',
              (v['tt'] as num?)?.toInt());
          final cur = byAnime[aid];
          if (cur == null || item.at > cur.at) byAnime[aid] = item;
        });
        final list = byAnime.values.toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        return list.take(limit).toList();
      });

  /// Everything for this profile (what gets pushed to the cloud).
  static Future<Map<String, dynamic>> all(String pid) =>
      _run(() async => _profile(await _readAll(), pid));

  /// Merge the cloud copy into local: the newer "t" wins per episode.
  static Future<void> mergeRemote(String pid, Map<String, dynamic> remote) =>
      _run(() async {
        final all = await _readAll();
        final prof = _profile(all, pid);
        remote.forEach((k, v) {
          if (v is! Map) return;
          final local = prof[k];
          final lt = local is Map ? ((local['t'] as num?)?.toInt() ?? 0) : -1;
          final rt = (v['t'] as num?)?.toInt() ?? 0;
          if (rt > lt) prof[k] = Map<String, dynamic>.from(v);
        });
        all[pid] = prof;
        await _writeAll(all);
      });
}
