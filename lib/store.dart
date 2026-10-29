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

  /// Website parity: the web never auto-creates a profile — a fresh guest
  /// with no profiles goes straight to Add Profile (create-first). So an
  /// empty store returns [], and callers route to AddProfileScreen.
  static Future<List<Profile>> profiles(String account) async {
    final all = await _read(_kProfiles);
    final list = (all[account] as List?) ?? [];
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

  /// Website parity: the auth gate remembers guest mode (like the web's
  /// localStorage auth state). Firebase session tokens are never persisted
  /// — only the guest choice survives a cold start.
  static Future<bool> isGuest() async {
    final p = await prefs;
    return p.getBool('ganime_is_guest') ?? false;
  }

  static Future<void> setGuest(bool v) async {
    final p = await prefs;
    await p.setBool('ganime_is_guest', v);
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

  /// Website parity: the web's Sync.getLast() is {at, status, detail}
  /// (e.g. {at: iso, status: 'synced', detail: 'Merged and synced'}).
  /// The Account screen's Cloud Sync card renders this record.
  static const _kLastSyncRecord = 'ganime_last_sync_record';

  static Future<Map<String, dynamic>?> syncRecord() async {
    final p = await prefs;
    final raw = p.getString(_kLastSyncRecord);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['at'] != null) return m;
      } catch (_) {}
    }
    // Back-compat: older builds stored only the ISO time.
    final iso = p.getString(_kLastSync);
    if (iso != null && iso.isNotEmpty) {
      return {'at': iso, 'status': 'synced'};
    }
    return null;
  }

  static Future<void> setSyncRecord({
    required String at,
    required String status,
    String? detail,
  }) async {
    final p = await prefs;
    await p.setString(
      _kLastSyncRecord,
      jsonEncode({
        'at': at,
        'status': status,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      }),
    );
  }

  /// Website parity: wipeDeviceData() — delete every local key
  /// (profiles, settings, addons, watched, library, tracking, caches,
  /// auth, firebase config) and let the caller route to a clean gate.
  /// Sign Out deliberately does NOT do this.
  static Future<void> wipeAll() async {
    final p = await prefs;
    await p.clear();
  }

  // ------------------------------------------------------------------
  // Firebase auth session (website parity: firebase.js persists the
  // full session — idToken + refreshToken + expiresAt + email + uid —
  // in localStorage and proactively refreshes the idToken when it
  // expires within 60s). Stored on-device ONLY, never synced to the
  // cloud doc (same rule as the web app).
  // ------------------------------------------------------------------
  static const _kFirebaseSession = 'ganime_firebase_session';

  static Future<Map<String, dynamic>> firebaseSession() async =>
      _read(_kFirebaseSession);

  static Future<void> saveFirebaseSession(Map<String, dynamic> v) async =>
      _write(_kFirebaseSession, v);

  static Future<void> clearFirebaseSession() async {
    final p = await prefs;
    await p.remove(_kFirebaseSession);
  }

  // ------------------------------------------------------------------
  // Home rails cache (website parity: loadLiveHome() renders cached
  // rails instantly and skips the network entirely when the cache is
  // < 120s old — this is what makes the website feel fast).
  // ------------------------------------------------------------------
  static const _kHomeRails = 'ganime_home_rails';
  static const _kHomeRailsTs = 'ganime_home_rails_ts';

  static Future<String?> homeRailsJson() async {
    final p = await prefs;
    return p.getString(_kHomeRails);
  }

  static Future<int> homeRailsTs() async {
    final p = await prefs;
    return p.getInt(_kHomeRailsTs) ?? 0;
  }

  static Future<void> saveHomeRails(String json, int tsMs) async {
    final p = await prefs;
    await p.setString(_kHomeRails, json);
    await p.setInt(_kHomeRailsTs, tsMs);
  }

  // ------------------------------------------------------------------
  // Library sort preference (website parity: librarySort, default
  // UPDATED_DESC, with the 8-option LIBRARY_SORTS menu).
  // ------------------------------------------------------------------
  static const _kLibrarySort = 'ganime_library_sort';

  static Future<String> librarySort() async {
    final p = await prefs;
    return p.getString(_kLibrarySort) ?? 'UPDATED_DESC';
  }

  static Future<void> setLibrarySort(String v) async {
    final p = await prefs;
    await p.setString(_kLibrarySort, v);
  }
}
