// Shared one-tap OAuth connect for AniList / MAL / Simkl.
// Used by the tracker dialog and the library tabs: launches the provider's
// authorize page in an in-app browser and waits for the /app-oauth return
// via App Links. Returns true on success, false on cancel/failure.
// No UI of its own — callers refresh their own state afterwards.
// (Logic mirrors TrackingSettingsScreen's _connect* handlers.)
import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../store.dart';
import 'oauth.dart';
import 'trackers.dart';

class TrackerOAuth {
  static const _appOAuthRedirect = 'https://ganime.pages.dev/app-oauth';
  /// Shared AppLinks instance — avoids leaking a new broadcast subscription
  /// on every connect attempt.
  static final AppLinks _links = AppLinks();
  static const _relayUrl = 'https://ganime-relay.gp237372.workers.dev';

  /// AniList client for the APP (redirect:
  /// https://ganime.pages.dev/app-oauth?provider=anilist).
  static const _anilistAppClientId = '54686';

  static Map<String, String> _frag(Uri u) {
    final m = <String, String>{};
    if (u.fragment.isEmpty) return m;
    for (final kv in u.fragment.split('&')) {
      final i = kv.indexOf('=');
      if (i > 0) m[kv.substring(0, i)] = Uri.decodeComponent(kv.substring(i + 1));
    }
    return m;
  }

  /// Waits for the browser to hand back to the app via /app-oauth.
  /// Handles cold start (app killed while the browser held the flow).
  static Future<Uri?> _waitLink(String provider, String state,
      {bool fragment = false}) async {
    final links = _links;
    bool matches(Uri? u) {
      if (u == null ||
          u.host != 'ganime.pages.dev' ||
          !u.path.startsWith('/app-oauth')) {
        return false;
      }
      if (u.queryParameters['provider'] != provider) return false;
      return fragment
          ? _frag(u)['state'] == state
          : u.queryParameters['state'] == state;
    }

    final initial = await links.getInitialLink();
    if (matches(initial)) return initial;
    try {
      return await links.uriLinkStream
          .firstWhere(matches)
          .timeout(const Duration(minutes: 2));
    } on StateError {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// AniList OAuth code flow. Returns true when the token was saved.
  static Future<bool> connectAnilist() async {
    try {
      final state = OAuthService.generateState();
      final redirect =
          Uri.encodeComponent('$_appOAuthRedirect?provider=anilist');
      final ok = await launchUrl(
        Uri.parse('https://anilist.co/api/v2/oauth/authorize'
            '?client_id=$_anilistAppClientId&redirect_uri=$redirect'
            '&response_type=code&state=$state'),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!ok) return false;
      // Code flow: AniList redirects with ?code=...&state=... (query, not fragment).
      final cb = await _waitLink('anilist', state);
      final code = cb?.queryParameters['code'];
      if (code == null) return false;
      final data = await OAuthService.exchangeAnilist(code);
      final tok = data['access_token'] as String;
      final v = await Trackers.anilistViewer(tok);
      final m = await Store.tracker();
      m['anilistToken'] = tok;
      m['anilistUserId'] = (v['id'] ?? '').toString();
      m['anilistUsername'] = (v['name'] ?? '').toString();
      await Store.saveTracker(m);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Simkl OAuth code flow (PKCE S256). Returns true when the token was saved.
  static Future<bool> connectSimkl() async {
    try {
      final verifier = OAuthService.generateVerifier();
      final challenge = OAuthService.s256Challenge(verifier);
      final state = OAuthService.generateState();
      final ok = await launchUrl(
          Uri.parse(OAuthService.simklAuthorizeUrl(challenge, state)),
          mode: LaunchMode.inAppBrowserView);
      if (!ok) return false;
      final cb = await _waitLink('simkl', state);
      final code = cb?.queryParameters['code'];
      if (code == null) return false;
      final data = await OAuthService.exchangeSimkl(code, verifier);
      final m = await Store.tracker();
      m['simklClientId'] = OAuthService.simklClientId;
      m['simklToken'] = data['access_token'];
      m['simklRefreshToken'] = data['refresh_token'] ?? '';
      m['simklExpiresAt'] = data['expires_in'] != null
          ? DateTime.now().millisecondsSinceEpoch +
              (data['expires_in'] as int) * 1000
          : 0;
      try {
        final r = await http.get(
            Uri.parse('https://api.simkl.com/users/settings'),
            headers: {
              'simkl-api-key': OAuthService.simklClientId,
              'Authorization': 'Bearer ${data['access_token']}',
            });
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final user = (j is Map) ? j['user'] : null;
        if (user is Map) {
          m['simklUsername'] =
              (user['name'] ?? user['username'] ?? '').toString();
        }
      } catch (_) {}
      await Store.saveTracker(m);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// MAL OAuth code flow (PKCE plain). Returns true when the token was saved.
  static Future<bool> connectMal() async {
    try {
      final verifier = OAuthService.generateVerifier();
      final state = OAuthService.generateState();
      final ok = await launchUrl(
          Uri.parse(OAuthService.malAuthorizeUrl(verifier, state)),
          mode: LaunchMode.inAppBrowserView);
      if (!ok) return false;
      final cb = await _waitLink('mal', state);
      final code = cb?.queryParameters['code'];
      if (code == null) return false;
      final data = await OAuthService.exchangeMal(code, verifier);
      var username = '';
      try {
        // Website parity: POST with access_token in body (not GET with header).
        final r = await http.post(
            Uri.parse('$_relayUrl/mal/me'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'access_token': data['access_token']}));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final d = j['data'] as Map?;
        username = ((d?['name'] ?? j['name']) ?? '').toString();
      } catch (_) {}
      final m = await Store.tracker();
      m['malClientId'] = OAuthService.malClientId;
      m['malToken'] = data['access_token'];
      m['malRefreshToken'] = data['refresh_token'] ?? '';
      m['malUsername'] = username;
      await Store.saveTracker(m);
      return true;
    } catch (_) {
      return false;
    }
  }
}
