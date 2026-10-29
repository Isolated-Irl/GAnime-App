// Local store (SharedPreferences, JSON). Local-first, like the web app.
// Profiles are namespaced per account: guest profiles live under 'guest',
// signed-in profiles under 'uid:<uid>'. Deleting a profile records a
// tombstone so a later cloud merge does not resurrect it.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class Store {
  static const _kProfiles = 'ganime_profiles';
  static const _kActiveProfile = 'ganime_active_profile';
  static const _kSettings = 'ganime_settings';
  static const _kWatched = 'ganime_watched'; // {profileId: {animeId: [ep, ...]}}
  static const _kSavedEps =
      'ganime_saved_eps'; // {profileId: {animeId: [ep, ...]}} — bookmarked episodes
  static const _kLibraryLocal = 'ganime_library_local';
  static const _kAddons = 'ganime_addons';
  static const _kTombstones = 'ganime_tombstones';
  static const _kTracker = 'ganime_tracker'; // tokens/ids, local only, never synced
  static const _kFirebase = 'ganime_firebase'; // user-entered config, local only
  static const _kLastSync = 'ganime_last_sync';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<Map<String, dynamic>> _read(String key) async {
    final p = await prefs;
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(String key, Map<String, dynamic> v) async {
    final p = await prefs;
    await p.setString(key, jsonEncode(v));
  }

  static Future<List<Profile>> profiles(String account) async {
    final all = await _read(_kProfiles);
    final list = (all[account] as List?) ?? [];
    if (list.isEmpty) {
      final seed = [const Profile(id: 'p1', name: 'Profile 1')];
      await saveProfiles(account, seed);
      return seed;
    }
    return list
        .map((e) => Profile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveProfiles(String account, List<Profile> ps) async {
    final all = await _read(_kProfiles);
    all[account] = ps.map((p) => p.toJson()).toList();
    await _write(_kProfiles, all);
  }

  static Future<String?> activeProfile(String account) async {
    final p = await prefs;
    return p.getString('$_kActiveProfile:$account');
  }

  static Future<void> setActiveProfile(String account, String id) async {
    final p = await prefs;
    await p.setString('$_kActiveProfile:$account', id);
  }

  static Future<AppSettings> settings() async {
    final m = await _read(_kSettings);
    return m.isEmpty ? const AppSettings() : AppSettings.fromJson(m);
  }

  static Future<void> saveSettings(AppSettings s) async {
    await _write(_kSettings, s.toJson());
  }

  // Watched episodes, per profile. Hole-preserving: unmark removes one ep.
  static Future<Set<int>> watched(String profileId, int animeId) async {
    final m = await _read(_kWatched);
    final prof = (m[profileId] as Map<String, dynamic>?) ?? {};
    final list = (prof['$animeId'] as List?) ?? [];
    return list.map((e) => (e as num).toInt()).toSet();
  }

  static Future<void> setWatched(
      String profileId, int animeId, Set<int> eps) async {
    final m = await _read(_kWatched);
    final prof = Map<String, dynamic>.from(
        (m[profileId] as Map<String, dynamic>?) ?? {});
    prof['$animeId'] = eps.toList();
    m[profileId] = prof;
    await _write(_kWatched, m);
  }

  static Future<Map<int, Set<int>>> allWatched(String profileId) async {
    final m = await _read(_kWatched);
    final prof = (m[profileId] as Map<String, dynamic>?) ?? {};
    final out = <int, Set<int>>{};
    prof.forEach((k, v) {
      out[int.tryParse(k) ?? 0] =
          ((v as List?) ?? []).map((e) => (e as num).toInt()).toSet();
    });
    return out;
  }

  /// Bookmarked ("saved") episodes per title, same shape as watched.
  static Future<Set<int>> savedEps(String profileId, int animeId) async {
    final m = await _read(_kSavedEps);
    final prof = (m[profileId] as Map<String, dynamic>?) ?? {};
    final list = (prof['$animeId'] as List?) ?? [];
    return list.map((e) => (e as num).toInt()).toSet();
  }

  static Future<void> setSavedEps(
      String profileId, int animeId, Set<int> eps) async {
    final m = await _read(_kSavedEps);
    final prof = Map<String, dynamic>.from(
        (m[profileId] as Map<String, dynamic>?) ?? {});
    prof['$animeId'] = eps.toList();
    m[profileId] = prof;
    await _write(_kSavedEps, m);
  }

  static Future<List<LibraryEntry>> localLibrary(String profileId) async {
    final m = await _read(_kLibraryLocal);
    final list = (m[profileId] as List?) ?? [];
    return list.map((e) {
      final j = e as Map<String, dynamic>;
      return LibraryEntry(
        key: '${j['key']}',
        source: 'local',
        title: (j['title'] as String?) ?? '',
        cover: (j['cover'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'CURRENT',
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt(),
        anilistId: (j['anilistId'] as num?)?.toInt(),
      );
    }).toList();
  }

  static Future<void> saveLocalLibrary(
      String profileId, List<LibraryEntry> entries) async {
    final m = await _read(_kLibraryLocal);
    m[profileId] = entries
        .map((e) => {
              'key': e.key,
              'title': e.title,
              'cover': e.cover,
              'status': e.status,
              'progress': e.progress,
              'total': e.total,
              'anilistId': e.anilistId,
            })
        .toList();
    await _write(_kLibraryLocal, m);
  }

  static Future<List<AddonRecord>> addons(String profileId) async {
    final m = await _read(_kAddons);
    final list = (m[profileId] as List?) ?? [];
    return list
        .map((e) => AddonRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAddons(
      String profileId, List<AddonRecord> addons) async {
    final m = await _read(_kAddons);
    m[profileId] = addons.map((a) => a.toJson()).toList();
    await _write(_kAddons, m);
  }

  static Future<Set<String>> tombstones() async {
    final m = await _read(_kTombstones);
    return ((m['ids'] as List?) ?? []).map((e) => '$e').toSet();
  }

  static Future<void> addTombstone(String id) async {
    final ids = await tombstones();
    ids.add(id);
    await _write(_kTombstones, {'ids': ids.toList()});
  }

  static Future<Map<String, dynamic>> tracker() async => _read(_kTracker);
  static Future<void> saveTracker(Map<String, dynamic> v) async =>
      _write(_kTracker, v);
  static Future<Map<String, dynamic>> firebaseConfig() async =>
      _read(_kFirebase);
  static Future<void> saveFirebaseConfig(Map<String, dynamic> v) async =>
      _write(_kFirebase, v);
  static Future<String?> lastSync() async {
    final p = await prefs;
    return p.getString(_kLastSync);
  }

  static Future<void> setLastSync(String v) async {
    final p = await prefs;
    await p.setString(_kLastSync, v);
  }
}
