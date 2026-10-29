// Firebase via REST — no google-services.json, no config in the repo.
// The user enters their own Firebase project config (apiKey + projectId)
// in Settings, stored ONLY on-device. Auth uses Identity Toolkit,
// Firestore uses the REST API with the user's idToken.
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
import '../models.dart';
import '../store.dart';

class FirebaseSync {
  String? _apiKey;
  String? _projectId;
  String? _idToken;
  String? _uid;

  String? get uid => _uid;
  bool get configured => _apiKey != null && _projectId != null;
  bool get signedIn => _idToken != null && _uid != null;

  Future<void> loadConfig() async {
    final cfg = await Store.firebaseConfig();
    _apiKey = (cfg['apiKey'] as String?)?.isNotEmpty == true
        ? cfg['apiKey'] as String
        : null;
    _projectId = (cfg['projectId'] as String?)?.isNotEmpty == true
        ? cfg['projectId'] as String
        : null;
  }

  Future<void> saveConfig(String apiKey, String projectId) async {
    // Merge: never clobber the persisted auth email.
    final cur = await Store.firebaseConfig();
    cur['apiKey'] = apiKey;
    cur['projectId'] = projectId;
    await Store.saveFirebaseConfig(cur);
    _apiKey = apiKey;
    _projectId = projectId;
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
    if (!configured) throw Exception('Firebase not configured in Settings.');
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
    // Remember the email on-device so Settings > Account can show it.
    final cfg = await Store.firebaseConfig();
    cfg['email'] = email;
    await Store.saveFirebaseConfig(cfg);
  }

  void signOut() {
    _idToken = null;
    _uid = null;
  }

  /// Sends a Firebase password-reset email (Identity Toolkit
  /// accounts:sendOobCode). Used by the "Forgot password?" button.
  Future<void> sendPasswordReset(String email) async {
    if (!configured) throw Exception('Firebase not configured in Settings.');
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

  /// Push local state to users/{uid}. Merge-first, matching the web app:
  /// pull remote, union profiles/addons (local wins), union watched and
  /// library entries by key, drop tombstoned profiles, newer settings
  /// win per key, then write the merged document.
  Future<void> push({
    required String account,
    required AppSettings settings,
    required List<Profile> profiles,
    required Map<int, Set<int>> watched,
    required List<LibraryEntry> localLibrary,
    required List<AddonRecord> addons,
    required Set<String> tombstones,
  }) async {
    if (!signedIn) throw Exception('Not signed in to Firebase.');
    final remoteDoc = await pullDocumentJson();
    final remote = remoteDoc ?? {};
    final remoteProfiles = (remote['profiles'] as List?) ?? [];
    final byId = <String, Map<String, dynamic>>{};
    for (final p in remoteProfiles) {
      final j = p as Map<String, dynamic>;
      byId['${j['id']}'] = j;
    }
    for (final p in profiles) {
      byId[p.id] = p.toJson();
    }
    for (final t in tombstones) {
      byId.remove(t);
    }
    final remoteAddons = (remote['addons'] as List?) ?? [];
    final addonByUrl = <String, Map<String, dynamic>>{};
    for (final a in remoteAddons) {
      final j = a as Map<String, dynamic>;
      addonByUrl['${j['manifestUrl']}'] = j;
    }
    for (final a in addons) {
      addonByUrl[a.manifestUrl] = a.toJson();
    }
    final remoteWatched =
        (remote['watched'] as Map<String, dynamic>?) ?? {};
    final mergedWatched = Map<String, dynamic>.from(remoteWatched);
    watched.forEach((animeId, eps) {
      final existing = ((mergedWatched['$animeId'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .toSet();
      mergedWatched['$animeId'] = {...existing, ...eps}.toList();
    });
    final remoteLib = (remote['localLibrary'] as List?) ?? [];
    final libByKey = <String, Map<String, dynamic>>{};
    for (final e in remoteLib) {
      final j = e as Map<String, dynamic>;
      libByKey['${j['key']}'] = j;
    }
    for (final e in localLibrary) {
      libByKey[e.key] = {
        'key': e.key,
        'title': e.title,
        'cover': e.cover,
        'status': e.status,
        'progress': e.progress,
        'total': e.total,
        'anilistId': e.anilistId,
      };
    }
    final remoteSettings =
        (remote['settings'] as Map<String, dynamic>?) ?? {};
    final remoteSettingsAt =
        (remote['settingsUpdatedAt'] as num?)?.toInt() ?? 0;
    // Local settings win only if they are the newer write; in this
    // app a push always carries the user's current settings, and the
    // timestamp is the push time, so a push never downgrades settings
    // that were written after the last pull (callers pull first).
    final now = DateTime.now().millisecondsSinceEpoch;
    final settingsJson = now >= remoteSettingsAt
        ? settings.toJson()
        : remoteSettings;
    final doc = {
      'version': 1,
      'updatedAt': now,
      'account': account,
      'settings': settingsJson,
      'settingsUpdatedAt': now >= remoteSettingsAt ? now : remoteSettingsAt,
      'profiles': byId.values.toList(),
      'watched': mergedWatched,
      'localLibrary': libByKey.values.toList(),
      'addons': addonByUrl.values.toList(),
      'tombstones': tombstones.toList(),
    };
    final body = {
      'fields': {
        'ganime': {'stringValue': jsonEncode(doc)},
        'updatedAt': {'integerValue': '$now'},
      },
    };
    final r = await http.patch(
      Uri.parse(_docUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_idToken',
      },
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) throw Exception('Firestore push failed: ${r.body}');
    await Store.setLastSync(DateTime.now().toIso8601String());
  }

  Future<Map<String, dynamic>?> pullRaw() async {
    if (!signedIn) return null;
    final r = await http.get(
      Uri.parse(_docUrl),
      headers: {'Authorization': 'Bearer $_idToken'},
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
    final ganime = fields['ganime'] as Map<String, dynamic>?;
    final s = ganime?['stringValue'] as String?;
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
