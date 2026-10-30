// One-tap tracker OAuth — Dart port of the website's flow.
// Simkl: code flow + PKCE S256 (REQUIRED) + scope media:read media:write
//        (scope-less tokens are READ-ONLY; writes 403 insufficient_scope)
// MAL:   code flow + PKCE plain. Both code->token swaps go through the
//        Cloudflare relay so the client secret never ships.
// AniList: token-in-fragment redirect flow.
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class TrackerOAuth {
  static const relayUrl = 'https://ganime-relay.gp237372.workers.dev';
  static const anilistClientId = '54686';
  static const simklClientId =
      '49dfaf44602c7464026066ff52eb2e4fb797f26a136a2107c250e5d9f73f8a7b';
  static const malClientId = 'f15fbfc461e31b1674c0747f5e680f01';
  static const redirectUri = 'https://ganime.pages.dev/app-oauth';

  static final _rng = Random.secure();
  static String randomString([int len = 64]) {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(len, (_) => c[_rng.nextInt(c.length)]).join();
  }

  static String pkceS256(String v) =>
      base64Url.encode(sha256.convert(utf8.encode(v)).bytes).replaceAll('=', '');

  static Uri simklUrl(String state, String challenge) => Uri.https(
      'simkl.com', '/oauth2/authorize', {
    'client_id': simklClientId, 'redirect_uri': redirectUri, 'state': state,
    'code_challenge': challenge, 'code_challenge_method': 'S256',
    'scope': 'media:read media:write',   // non-negotiable
  });

  static Uri malUrl(String state, String verifier) => Uri.https(
      'myanimelist.net', '/v1/oauth2/authorize', {
    'client_id': malClientId, 'redirect_uri': redirectUri, 'state': state,
    'code_challenge': verifier, 'code_challenge_method': 'plain',
  });

  static Uri anilistUrl(String state) => Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize?client_id=$anilistClientId'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}&state=$state&token');

  static Future<void> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final r = await http.post(Uri.parse('$relayUrl$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode != 200) throw Exception('$path (${r.statusCode}): ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> exchangeSimkl(String code, String v) =>
      _post('/exchange/simkl', {'code': code, 'code_verifier': v, 'redirect_uri': redirectUri});
  static Future<Map<String, dynamic>> exchangeMal(String code, String v) =>
      _post('/exchange/mal', {'code': code, 'code_verifier': v, 'redirect_uri': redirectUri});
  static Future<Map<String, dynamic>> refreshSimkl(String rt) =>
      _post('/refresh/simkl', {'refresh_token': rt});

  static Future<Map<String, dynamic>> malMe(String token) async {
    final r = await http.get(Uri.parse('$relayUrl/mal/me'),
        headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode != 200) throw Exception('mal/me: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Parses the app-link callback. Handles ?code= (Simkl/MAL) and the
  /// AniList fragment form ...#access_token=..&state=..
  static Map<String, String> parseCallback(Uri uri) {
    final out = <String, String>{};
    uri.queryParameters.forEach((k, v) => out[k] = v);
    if (uri.fragment.isNotEmpty) {
      for (final kv in uri.fragment.split('&')) {
        final i = kv.indexOf('=');
        if (i > 0) out[kv.substring(0, i)] = Uri.decodeComponent(kv.substring(i + 1));
      }
    }
    return out;
  }
}
