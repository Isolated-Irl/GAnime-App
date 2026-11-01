// Resume-position store: remembers WHERE you stopped in every episode,
// per profile, on-device (SharedPreferences) and merged into the cloud doc.
//
// Shape: {profileId: {"animeId:ep": {"p": posMs, "d": durMs, "t": savedAtMs, "x": 1?}}}
//  - "x":1 means "finished / cleared" (kept as a tombstone so an older cloud
//    copy can't bring the spot back after you finished the episode).
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ResumeEntry {
  final int posMs, durMs, at;
  const ResumeEntry(this.posMs, this.durMs, this.at);
}

class ResumeStore {
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
          String pid, int animeId, int ep, int posMs, int durMs) =>
      _put(pid, animeId, ep,
          {'p': posMs, 'd': durMs, 't': DateTime.now().millisecondsSinceEpoch});

  /// Finished episode: forget the spot (tombstone so the cloud copy dies too).
  static Future<void> clear(String pid, int animeId, int ep) => _put(pid,
      animeId, ep, {'p': 0, 'd': 0, 't': DateTime.now().millisecondsSinceEpoch, 'x': 1});

  static Future<void> _put(
          String pid, int animeId, int ep, Map<String, dynamic> v) =>
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
