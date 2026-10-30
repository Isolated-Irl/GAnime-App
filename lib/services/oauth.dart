// OAuth one-tap for MAL and Simkl — website parity.
// The website uses OAuth authorization-code flow with PKCE:
// 1. App generates PKCE verifier/challenge + state
// 2. Opens browser to provider's authorize URL
// 3. User approves, gets redirected to ganime.pages.dev/?provider=X&code=...
// 4. User copies the code, pastes in app
// 5. App exchanges code via relay for tokens
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class OAuthService {
  // Public IDs from website's config.js — safe to ship.
  static const malClientId = 'f15fbfc461e31b1674c0747f5e680f01';
  static const simklClientId =
      '49dfaf44602c7464026066ff52eb2e4fb797f26a136a2107c250e5d9f73f8a7b';
  static const relayUrl = 'https://ganime-relay.gp237372.workers.dev';

  static String _oauthRedirect(String provider) =>
      'https://ganime.pages.dev/app-oauth?provider=$provider';

  /// Generate a random PKCE verifier (128 chars, URL-safe).
  static String generateVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(128, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Generate a random state (32 chars).
  static String generateState() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// S256 challenge for Simkl: base64url(sha256(verifier)).
  static String s256Challenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// MAL authorize URL (PKCE plain: challenge == verifier).
  static String malAuthorizeUrl(String verifier, String state) {
    final redirect = _oauthRedirect('mal');
    return 'https://myanimelist.net/v1/oauth2/authorize'
        '?response_type=code'
        '&client_id=${Uri.encodeComponent(malClientId)}'
        '&state=${Uri.encodeComponent(state)}'
        '&redirect_uri=${Uri.encodeComponent(redirect)}'
        '&code_challenge=${Uri.encodeComponent(verifier)}'
        '&code_challenge_method=plain';
  }

  /// Simkl authorize URL (PKCE S256).
  static String simklAuthorizeUrl(String challenge, String state) {
    final redirect = _oauthRedirect('simkl');
    // Simkl requires scope for write access (Phase 1: without scope,
    // token is read-only).
    const scope = 'media:read media:write';
    return 'https://simkl.com/oauth2/authorize'
        '?response_type=code'
        '&client_id=${Uri.encodeComponent(simklClientId)}'
        '&redirect_uri=${Uri.encodeComponent(redirect)}'
        '&state=${Uri.encodeComponent(state)}'
        '&scope=${Uri.encodeComponent(scope)}'
        '&code_challenge=${Uri.encodeComponent(challenge)}'
        '&code_challenge_method=S256';
  }

  /// Exchange MAL code for tokens via relay.
  static Future<Map<String, dynamic>> exchangeMal(
      String code, String verifier) async {
    final redirect = _oauthRedirect('mal');
    final r = await http.post(
      Uri.parse('$relayUrl/exchange/mal'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
      }),
    );
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['access_token'] == null) {
      throw Exception(data['error'] ?? data['message'] ?? 'MAL exchange failed');
    }
    return data;
  }

  /// Exchange Simkl code for tokens via relay.
  static Future<Map<String, dynamic>> exchangeSimkl(
      String code, String verifier) async {
    final redirect = _oauthRedirect('simkl');
    final r = await http.post(
      Uri.parse('$relayUrl/exchange/simkl'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
      }),
    );
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['access_token'] == null) {
      throw Exception(
          data['error_description'] ?? data['error'] ?? 'Simkl exchange failed');
    }
    return data;
  }

  /// Exchange AniList authorization code for tokens via relay.
  /// (AniList dropped implicit flow; code flow is required.)
  static Future<Map<String, dynamic>> exchangeAnilist(String code) async {
    final redirect = _oauthRedirect('anilist');
    final r = await http.post(
      Uri.parse('$relayUrl/exchange/anilist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'redirect_uri': redirect,
      }),
    );
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['access_token'] == null) {
      // AniList returns errors as {errors: [{message: ...}]}, relay may
      // return {error: ...} — surface the real message for diagnosis.
      var msg = 'AniList exchange failed';
      final errs = data['errors'] as List?;
      if (errs != null && errs.isNotEmpty) {
        final m = (errs.first as Map?)?['message'];
        if (m != null) msg = 'AniList: $m';
      } else if (data['error'] != null) {
        msg = 'AniList: ${data['error_description'] ?? data['error']}';
      } else if (data['message'] != null) {
        msg = 'AniList: ${data['message']}';
      }
      throw Exception(msg);
    }
    return data;
  }
}
