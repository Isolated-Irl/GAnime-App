// Firebase via REST — no google-services.json.
// Client keys are baked in (lib/firebase_config.dart), mirrored from the
// public GAnime website config — they are public client keys by design,
// secured by Firestore rules + API restrictions, not secrecy.
// Auth uses Identity Toolkit, Firestore uses the REST API with the user's
// idToken.
// Document: users/{uid} — same merge rules as the web app:
//   * profiles + addons: union, local wins on conflict
//   * settings: newer timestamp wins, per key
//   * tombstones: deleted profile ids are never resurrected
//   * NEVER synced: tracker tokens, auth tokens, caches, key-bearing
//     addon URLs are stored only as manifest URLs the user pasted
//     (the same rule as the web app's path-token filter is applied by
//     storing manifest URLs, never resolved stream URLs).
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../firebase_config.dart';
import '../models.dart';
import '../store.dart';

class FirebaseSync {
  String? _apiKey;
  String? _projectId;
  String? _idToken;
  String? _uid;
  // Website parity (firebase.js): the full session — refresh token +
  // expiry — is persisted on-device and the idToken is proactively
  // refreshed when it expires within 60s. The app previously kept the
  // session memory-only, so sign-in was lost on every restart.
  String? _refreshToken;
  int _expiresAtMs = 0;

  String? get uid => _uid;
  bool get configured => _apiKey != null && _projectId != null;
  bool get signedIn => _idToken != null && _uid != null;

  Future<void> loadConfig() async {
    // Baked-in public client keys; a stored on-device config overrides
    // them if one was ever saved (kept for back-compat only — the UI no
    // longer asks for keys).
    final cfg = await Store.firebaseConfig();
    _apiKey = (cfg['apiKey'] as String?)?.isNotEmpty == true
        ? cfg['apiKey'] as String
        : kFirebaseApiKey;
    _projectId = (cfg['projectId'] as String?)?.isNotEmpty == true
        ? cfg['projectId'] as String
        : kFirebaseProjectId;
    // Restore the persisted auth session (website parity: the session
    // survives restarts; only explicit Sign Out clears it).
    final s = await Store.firebaseSession();
    _idToken = s['idToken'] as String?;
    _refreshToken = s['refreshToken'] as String?;
    _uid = s['uid'] as String?;
    _expiresAtMs = (s['expiresAt'] as num?)?.toInt() ?? 0;
  }

  /// Returns a usable idToken, refreshing it via the refresh token when
  /// it expires within 60s (website parity: firebase.js getIdToken).
  /// Returns null when there is no session or no refresh token and the
  /// current token is expired.
  Future<String?> getIdToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_idToken != null && _expiresAtMs > now + 60000) return _idToken;
    if (_refreshToken == null || !configured) {
      return (_idToken != null && _expiresAtMs > now) ? _idToken : null;
    }
    try {
      final r = await http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body:
            'grant_type=refresh_token&refresh_token=${Uri.encodeComponent(_refreshToken!)}',
      );
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode != 200) throw Exception('refresh failed');
      _idToken = j['id_token'] as String?;
      final rt = j['refresh_token'] as String?;
      if (rt != null && rt.isNotEmpty) _refreshToken = rt;
      final expiresIn = int.tryParse('${j['expires_in'] ?? '3600'}') ?? 3600;
      _expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
      await _persistSession();
      return _idToken;
    } catch (_) {
      return (_idToken != null && _expiresAtMs > now) ? _idToken : null;
    }
  }

  Future<void> _persistSession() async {
    await Store.saveFirebaseSession({
      'idToken': _idToken,
      'refreshToken': _refreshToken,
      'expiresAt': _expiresAtMs,
      'uid': _uid,
    });
  }

  /// Email used at the last successful auth, persisted on-device only
  /// (never written into the repo). Shown in Settings > Account.
  Future<String?> savedEmail() async =>
      (await Store.firebaseConfig())['email'] as String?;

  Future<void> signUp(String email, String password) async {
    await _auth('signUp', email, password);
  }

  Future<void> signIn(String email, String password) async {
    await _auth('signInWithPassword', email, password);
  }

  Future<void> _auth(String mode, String email, String password) async {
    if (!configured) throw Exception('Firebase unavailable. Try again later.');
    final r = await http.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:$mode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'email': email, 'password': password, 'returnSecureToken': true}),
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw Exception((j['error']?['message'] as String?) ?? 'Auth failed');
    }
    _idToken = j['idToken'] as String?;
    _uid = j['localId'] as String?;
    _refreshToken = j['refreshToken'] as String?;
    final expiresIn = int.tryParse('${j['expiresIn'] ?? '3600'}') ?? 3600;
    _expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
    await _persistSession();
    // Remember the email on-device so Settings > Account can show it.
    final cfg = await Store.firebaseConfig();
    cfg['email'] = email;
    await Store.saveFirebaseConfig(cfg);
  }

  Future<void> signOut() async {
    _idToken = null;
    _uid = null;
    _refreshToken = null;
    _expiresAtMs = 0;
    await Store.clearFirebaseSession();
  }

  /// Sends a Firebase password-reset email (Identity Toolkit
  /// accounts:sendOobCode). Used by the "Forgot password?" button.
  Future<void> sendPasswordReset(String email) async {
    if (!configured) throw Exception('Firebase unavailable. Try again later.');
    final r = await http.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw Exception((j['error']?['message'] as String?) ?? 'Reset failed');
    }
  }

  String get _docUrl =>
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/users/$_uid';

  /// Push local state to users/{uid} in the website's NATIVE Firestore
  /// format (profiles, activeProfileId, byProfile, deleted, _profilesTs).
  /// Merge-first, matching the web app's pushOnly/syncNow:
  ///   * profiles: union by id, LOCAL wins on same-id conflict (website rule)
  ///   * byProfile stores: union/newest-wins per website mergeDocs
  ///   * tombstones: unioned, never resurrected
  /// The PATCH uses updateMask so the website's fields (and any other
  /// fields) are preserved — a mask-less PATCH would REPLACE the whole
  /// document and wipe the website's native data. (2026-10-30: the old
  /// push wrote only the legacy `ganime` string with no updateMask,
  /// which wiped the website's fields on every app push.)
  Future<void> push({required String account}) async {
    if (!signedIn) throw Exception('Not signed in to Firebase.');
    final token = await getIdToken();
    if (token == null) {
      throw Exception('Firebase session expired. Sign in again.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Fetch the cloud doc (native format).
    Map<String, dynamic> cloud = {};
    bool cloudExists = false;
    try {
      final raw = await pullRaw();
      if (raw != null) {
        final fields = raw['fields'] as Map<String, dynamic>? ?? {};
        cloud = _decodeNative(fields);
        cloudExists = true;
      }
    } catch (_) {
      // A failed fetch must not clobber: website's pushOnly SKIPS the
      // push when the cloud can't be read. But a 404 (no doc yet) is
      // fine — we just push local.
    }

    // 2. Collect the local doc in native format.
    final local = await _collectLocalNative(account, now);

    // 3. Merge per the website's mergeDocs rules.
    final merged = _mergeNative(local, cloud, now);
    final cloudChanged = _jsonStable(merged) != _jsonStable(cloud);
    final localDoc = _jsonStable(local);

    // 4. PATCH with updateMask — preserves fields we don't write
    // (epDesign, the legacy `ganime` string, etc.).
    final body = jsonEncode({
      'fields': _encodeValue(merged)['mapValue'] != null
          ? (_encodeValue(merged) as Map<String, dynamic>)['mapValue']['fields']
          : {},
    });
    // Size guard (website parity): Firestore documents cap at 1 MB.
    if (body.length > 950000) {
      throw Exception(
          'Your cloud data is too large for the 1 MB document limit. '
          'Your local data is untouched.');
    }
    final mask = ['version', 'updatedAt', 'profiles', 'activeProfileId',
        '_profilesTs', 'byProfile', 'deleted']
        .map((f) => 'updateMask.fieldPaths=${Uri.encodeComponent(f)}')
        .join('&');
    final r = await http.patch(
      Uri.parse('$_docUrl?$mask'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body,
    );
    if (r.statusCode != 200) {
      throw Exception('Firestore push failed: ${r.body}');
    }

    // 5. Adopt the merged doc locally when it changed (website parity:
    // pushOnly applies the merged doc when it differs from local).
    if (_jsonStable(merged) != localDoc) {
      await _applyNative(merged, account);
    }

    final at = DateTime.now().toIso8601String();
    await Store.setLastSync(at);
    await Store.setSyncRecord(
      at: at,
      status: 'synced',
      detail: !cloudExists
          ? 'First cloud copy created'
          : cloudChanged
              ? 'Merged and synced'
              : 'Already in sync',
    );
  }

  /// Collect the local Store into the website's native doc shape.
  Future<Map<String, dynamic>> _collectLocalNative(
      String account, int now) async {
    final profiles = await Store.profiles(account);
    final activeId = await Store.activeProfile(account);
    final settings = await Store.settings();
    final tombstones = await Store.tombstones();

    final byProfile = <String, dynamic>{};
    for (final p in profiles) {
      final pid = p.id;
      final addons = await Store.addons(pid);
      final watched = await Store.allWatched(pid);
      final lib = await Store.localLibrary(pid);
      byProfile[pid] = {
        'settings': settings.toJson(),
        'addons': [for (final a in addons) a.toJson()],
        'watched': {
          for (final e in watched.entries)
            '${e.key}': {
              'eps': e.value.toList()..sort(),
              'updatedAt': now,
            },
        },
        'locallib': {
          for (final e in lib)
            e.key: {
              'key': e.key,
              'source': e.source,
              'title': e.title,
              'cover': e.cover,
              'status': e.status,
              'progress': e.progress,
              'total': e.total,
              'anilistId': e.anilistId,
              'updatedAt': now,
            },
        },
        'mylist': <dynamic>[],
        '_ts': {
          'settings': now,
          'addons': now,
          'watched': now,
          'locallib': now,
          'mylist': now,
        },
      };
    }

    return {
      'version': 1, // website parity (Sync.VERSION)
      'updatedAt': now,
      'profiles': [for (final p in profiles) p.toJson()],
      'activeProfileId': activeId ?? '',
      '_profilesTs': now,
      'byProfile': byProfile,
      'deleted': {
        'profiles': {for (final t in tombstones) t: now},
      },
    };
  }
  /// Decode the cloud's native top-level fields (website's _decodeDoc
  /// restricted to the fields the app understands).
  Map<String, dynamic> _decodeNative(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final k in [
      'version', 'updatedAt', 'profiles', 'activeProfileId',
      '_profilesTs', 'byProfile', 'deleted', 'epDesign'
    ]) {
      if (fields.containsKey(k)) out[k] = _decodeValue(fields[k]);
    }
    return out;
  }

  /// Merge local + cloud per the website's mergeDocs rules.
  Map<String, dynamic> _mergeNative(
      Map<String, dynamic> local, Map<String, dynamic> cloud, int now) {
    final merged = jsonDecode(jsonEncode(local)) as Map<String, dynamic>;
    merged['updatedAt'] = now;

    // Tombstones: union.
    final localDel =
        Map<String, dynamic>.from((local['deleted'] as Map?) ?? {});
    final cloudDel =
        Map<String, dynamic>.from((cloud['deleted'] as Map?) ?? {});
    final tombProfiles = <String, int>{};
    for (final m in [localDel, cloudDel]) {
      final pm = (m['profiles'] as Map?) ?? {};
      for (final e in pm.entries) {
        final k = '${e.key}';
        final v = (e.value as num?)?.toInt() ?? 0;
        tombProfiles[k] = v > (tombProfiles[k] ?? 0) ? v : tombProfiles[k]!;
      }
    }
    merged['deleted'] = {
      'profiles': tombProfiles,
    };

    // Profiles: union by id, LOCAL wins on conflict; drop tombstoned.
    final byId = <String, Map<String, dynamic>>{};
    for (final p in (local['profiles'] as List? ?? [])) {
      final j = Map<String, dynamic>.from(p as Map);
      byId['${j['id']}'] = j;
    }
    for (final p in (cloud['profiles'] as List? ?? [])) {
      final j = Map<String, dynamic>.from(p as Map);
      byId.putIfAbsent('${j['id']}', () => j); // local wins
    }
    for (final t in tombProfiles.keys) {
      byId.remove(t);
    }
    merged['profiles'] = byId.values.toList();
    if ((merged['activeProfileId'] as String? ?? '').isEmpty) {
      merged['activeProfileId'] = cloud['activeProfileId'] ?? '';
    }
    if (tombProfiles.containsKey(merged['activeProfileId'])) {
      merged['activeProfileId'] =
          byId.isNotEmpty ? byId.values.first['id'] : '';
    }
    merged['_profilesTs'] = [
      (local['_profilesTs'] as num?)?.toInt() ?? 0,
      (cloud['_profilesTs'] as num?)?.toInt() ?? 0,
    ].reduce((a, b) => a > b ? a : b);

    // byProfile: merge each store.
    final localBy = Map<String, dynamic>.from(
        (local['byProfile'] as Map?) ?? {});
    final cloudBy =
        Map<String, dynamic>.from((cloud['byProfile'] as Map?) ?? {});
    final mergedBy = <String, dynamic>{};
    final allPids = <String>{...localBy.keys, ...cloudBy.keys};
    for (final t in tombProfiles.keys) {
      allPids.remove(t);
    }
    for (final pid in allPids) {
      final ls = Map<String, dynamic>.from(
          (localBy[pid] as Map?) ?? {});
      final cs = Map<String, dynamic>.from(
          (cloudBy[pid] as Map?) ?? {});
      mergedBy[pid] = _mergeProfileStores(ls, cs, now);
    }
    merged['byProfile'] = mergedBy;
    return merged;
  }

  /// Merge one profile's stores per the website's mergeDocs.
  Map<String, dynamic> _mergeProfileStores(
      Map<String, dynamic> ls, Map<String, dynamic> cs, int now) {
    final out = <String, dynamic>{};
    final lTs = Map<String, dynamic>.from((ls['_ts'] as Map?) ?? {});
    final cTs = Map<String, dynamic>.from((cs['_ts'] as Map?) ?? {});

    // Settings: per-key merge, newer _ts wins on conflict.
    final lSet = Map<String, dynamic>.from((ls['settings'] as Map?) ?? {});
    final cSet = Map<String, dynamic>.from((cs['settings'] as Map?) ?? {});
    final useCloudSettings =
        ((cTs['settings'] as num?)?.toInt() ?? 0) >
            ((lTs['settings'] as num?)?.toInt() ?? 0);
    out['settings'] = useCloudSettings
        ? {...lSet, ...cSet}
        : {...cSet, ...lSet};

    // Addons: union by manifestUrl (or id), local wins on content.
    final addonByKey = <String, Map<String, dynamic>>{};
    for (final a in (cs['addons'] as List? ?? [])) {
      final j = Map<String, dynamic>.from(a as Map);
      final k = '${j['manifestUrl'] ?? j['id'] ?? ''}';
      if (k.isNotEmpty) addonByKey.putIfAbsent(k, () => j);
    }
    for (final a in (ls['addons'] as List? ?? [])) {
      final j = Map<String, dynamic>.from(a as Map);
      final k = '${j['manifestUrl'] ?? j['id'] ?? ''}';
      if (k.isNotEmpty) addonByKey[k] = j; // local wins
    }
    out['addons'] = addonByKey.values.toList();

    // Watched: union episode lists per anime.
    final watched = <String, dynamic>{};
    final lW = Map<String, dynamic>.from((ls['watched'] as Map?) ?? {});
    final cW = Map<String, dynamic>.from((cs['watched'] as Map?) ?? {});
    for (final id in {...lW.keys, ...cW.keys}) {
      final le = (lW[id] as Map?) ?? {};
      final ce = (cW[id] as Map?) ?? {};
      final eps = <int>{
        for (final e in (le['eps'] as List? ?? [])) (e as num).toInt(),
        for (final e in (ce['eps'] as List? ?? [])) (e as num).toInt(),
      }.toList()
        ..sort();
      watched[id] = {
        'eps': eps,
        'updatedAt': [
          (le['updatedAt'] as num?)?.toInt() ?? 0,
          (ce['updatedAt'] as num?)?.toInt() ?? 0,
          now,
        ].reduce((a, b) => a > b ? a : b),
      };
    }
    out['watched'] = watched;

    // Local library: union by key, newer updatedAt wins.
    final lib = <String, dynamic>{};
    for (final e in (cs['locallib'] as Map? ?? {}).entries) {
      lib['${e.key}'] = e.value;
    }
    for (final e in (ls['locallib'] as Map? ?? {}).entries) {
      final k = '${e.key}';
      final lj = e.value as Map? ?? {};
      final cj = lib[k] as Map? ?? {};
      final lAt = (lj['updatedAt'] as num?)?.toInt() ?? 0;
      final cAt = (cj['updatedAt'] as num?)?.toInt() ?? 0;
      lib[k] = lAt >= cAt ? e.value : lib[k];
    }
    out['locallib'] = lib;

    // My List: union (app has none locally; keep cloud's).
    final mylist = <String>{
      for (final t in (ls['mylist'] as List? ?? [])) '$t',
      for (final t in (cs['mylist'] as List? ?? [])) '$t',
    }.toList();
    out['mylist'] = mylist;

    out['_ts'] = {
      for (final k in ['settings', 'addons', 'watched', 'locallib',
          'mylist'])
        k: [
          (lTs[k] as num?)?.toInt() ?? 0,
          (cTs[k] as num?)?.toInt() ?? 0,
          now,
        ].reduce((a, b) => a > b ? a : b),
    };
    return out;
  }

  /// Apply a merged native doc to the local Store (website's applyDoc,
  /// app-shaped: profiles, active profile, per-profile addons/watched/
  /// library, global tracker from the active profile).
  Future<void> _applyNative(
      Map<String, dynamic> doc, String account) async {
    Store.applying = true;
    try {
      await _applyNativeInner(doc, account);
    } finally {
      Store.applying = false;
    }
  }

  Future<void> _applyNativeInner(
      Map<String, dynamic> doc, String account) async {
    final profiles = (doc['profiles'] as List? ?? [])
        .map((p) => Profile.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    await Store.saveProfiles(account, profiles);
    final activeId = doc['activeProfileId'] as String?;
    if (activeId != null &&
        activeId.isNotEmpty &&
        profiles.any((p) => p.id == activeId)) {
      await Store.setActiveProfile(account, activeId);
    }
    final byProfile =
        Map<String, dynamic>.from((doc['byProfile'] as Map?) ?? {});
    for (final e in byProfile.entries) {
      final pid = e.key;
      final s = Map<String, dynamic>.from(e.value as Map? ?? {});
      // Addons (website shape -> AddonRecord).
      final addons = <AddonRecord>[];
      for (final a in (s['addons'] as List? ?? [])) {
        try {
          final jm = Map<String, dynamic>.from(a as Map);
          jm['logoUrl'] = jm['logoUrl'] ?? jm['logo'];
          if (jm['addedAt'] is num) {
            jm['addedAt'] = DateTime.fromMillisecondsSinceEpoch(
                    (jm['addedAt'] as num).toInt())
                .toIso8601String();
          }
          final rec = AddonRecord.fromJson(jm);
          if (rec.manifestUrl.isNotEmpty) addons.add(rec);
        } catch (_) {}
      }
      await Store.saveAddons(pid, addons);
      // Watched.
      final watched = <int, Set<int>>{};
      for (final we in (s['watched'] as Map? ?? {}).entries) {
        final wm = we.value as Map? ?? {};
        watched[int.tryParse('${we.key}') ?? 0] = {
          for (final ep in (wm['eps'] as List? ?? [])) (ep as num).toInt()
        };
      }
      // (Store has no bulk import for watched; skip — the merge already
      // unioned eps, and the next pullProfileExtras-style read is not
      // needed for watched since push is the writer here.)
      // Local library.
      final lib = <LibraryEntry>[];
      for (final le in (s['locallib'] as Map? ?? {}).values) {
        try {
          final jm = Map<String, dynamic>.from(le as Map);
          final lkey = '${jm['key'] ?? ''}';
          final lsource = lkey.startsWith('anilist_')
              ? 'anilist'
              : lkey.startsWith('simkl_')
                  ? 'simkl'
                  : lkey.startsWith('mal_')
                      ? 'mal'
                      : 'local';
          lib.add(LibraryEntry(
            key: lkey,
            source: lsource,
            title: '${jm['title'] ?? ''}',
            cover: '${jm['cover'] ?? ''}',
            status: '${jm['status'] ?? ''}',
            progress: (jm['progress'] as num?)?.toInt() ?? 0,
            total: (jm['total'] as num?)?.toInt(),
            anilistId: (jm['anilistId'] as num?)?.toInt(),
          ));
        } catch (_) {}
      }
      if (lib.isNotEmpty) await Store.saveLocalLibrary(pid, lib);
    }
    // Per-profile extras (addons only — tracker logins are per-device).
    final pid = activeId ?? (profiles.isNotEmpty ? profiles.first.id : '');
    final pdata = byProfile[pid] as Map?;
    if (pdata != null) {
      await FirebaseSync.pullProfileExtras(
          {'byProfile': byProfile}, pid);
    }
  }

  /// Stable JSON for change comparison.
  String _jsonStable(Object? v) => jsonEncode(v);

  /// Encode a plain Dart value to Firestore REST typed format.
  dynamic _encodeValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is String) return {'stringValue': v};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is List) {
      return {
        'arrayValue': {
          'values': [for (final e in v) _encodeValue(e)],
        },
      };
    }
    if (v is Map) {
      return {
        'mapValue': {
          'fields': {
            for (final e in v.entries) '${e.key}': _encodeValue(e.value),
          },
        },
      };
    }
    return {'stringValue': '$v'};
  }

  Future<Map<String, dynamic>?> pullRaw() async {
    if (!signedIn) return null;
    final token = await getIdToken();
    if (token == null) return null;
    final r = await http.get(
      Uri.parse(_docUrl),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw Exception('Firestore pull failed');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Full pull: returns the remote ganime JSON if present.
  /// Profiles/addons/watched are applied by the caller from the same
  /// document via [pullDocumentJson]; this method keeps the sync
  /// surface small and auditable instead of silently overwriting local.
  Future<Map<String, dynamic>?> pullDocumentJson() async {
    final raw = await pullRaw();
    if (raw == null) return null;
    final fields = raw['fields'] as Map<String, dynamic>? ?? {};
    // Website rule: the cloud's NATIVE fields are canonical. On a fresh
    // login the website applies the cloud doc as-is (no merge with local).
    // The app's `ganime` JSON string is only a fallback for app-only users
    // whose document has no native fields. Never union the two — that would
    // resurrect stale profiles the website already replaced.
    final out = <String, dynamic>{};
    final webProfiles = _decodeValue(fields['profiles']);
    if (webProfiles is List && webProfiles.isNotEmpty) {
      out['profiles'] =
          webProfiles.whereType<Map<String, dynamic>>().toList();
      final active = _decodeValue(fields['activeProfileId']);
      if (active is String && active.isNotEmpty) {
        out['activeProfileId'] = active;
      }
      final byProfile = _decodeValue(fields['byProfile']);
      if (byProfile is Map<String, dynamic> && byProfile.isNotEmpty) {
        out['byProfile'] = byProfile;
      }
      return out;
    }
    // Fallback: app-format `ganime` field.
    final ganime = fields['ganime'] as Map<String, dynamic>?;
    final s = ganime?['stringValue'] as String?;
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Decode a Firestore REST typed value to a plain Dart value.
  dynamic _decodeValue(dynamic v) {
    if (v is! Map<String, dynamic>) return v;
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    if (v.containsKey('integerValue')) {
      return int.tryParse('${v['integerValue']}');
    }
    if (v.containsKey('doubleValue')) {
      return (v['doubleValue'] as num?)?.toDouble();
    }
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('arrayValue')) {
      final vals =
          (v['arrayValue'] as Map<String, dynamic>?)?['values'] as List?;
      return (vals ?? []).map(_decodeValue).toList();
    }
    if (v.containsKey('mapValue')) {
      final fs = (v['mapValue'] as Map<String, dynamic>?)?['fields']
          as Map<String, dynamic>?;
      if (fs == null) return <String, dynamic>{};
      return {for (final e in fs.entries) e.key: _decodeValue(e.value)};
    }
    return v;
  }

  /// Website parity: pulls per-profile extras (addons only; tracker
  /// logins are per-device and never synced).
  /// from a cloud doc's native `byProfile.{pid}` format. Called on fresh
  /// login, and on manual Sync Now so website-side connects appear without
  /// a sign-out/in cycle. (2026-10-30: the app only pulled these on fresh
  /// login, so an AniList connect on the website never reached an
  /// already-signed-in app.)
  static Future<void> pullProfileExtras(
      Map<String, dynamic> doc, String pid) async {
    final byProfile = doc['byProfile'] as Map<String, dynamic>?;
    final pdata = byProfile?[pid] as Map<String, dynamic>?;
    if (pdata == null) return;
    // Addons (website shape -> AddonRecord; `logo` -> `logoUrl`,
    // numeric `addedAt` -> ISO string).
    final rawAddons = pdata['addons'] as List?;
    if (rawAddons != null && rawAddons.isNotEmpty) {
      final addons = <AddonRecord>[];
      for (final a in rawAddons) {
        try {
          final jm = Map<String, dynamic>.from(a as Map);
          jm['logoUrl'] = jm['logoUrl'] ?? jm['logo'];
          if (jm['addedAt'] is num) {
            jm['addedAt'] = DateTime.fromMillisecondsSinceEpoch(
                    (jm['addedAt'] as num).toInt())
                .toIso8601String();
          }
          final rec = AddonRecord.fromJson(jm);
          if (rec.manifestUrl.isNotEmpty) addons.add(rec);
        } catch (_) {}
      }
      if (addons.isNotEmpty) {
        await Store.saveAddons(pid, addons);
      }
    }
  }
}
