// Settings > Tracking — ONE-TAP OAuth only (App Links auto-return).
// The browser now hands back to the app automatically via the verified
// /app-oauth link, so the old manual paste/PIN flow is gone.
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../store.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../services/trackers.dart';
import '../../services/oauth.dart';
import 'settings_shell.dart';

class TrackingSettingsScreen extends StatefulWidget {
  const TrackingSettingsScreen(
      {super.key, required this.settings, required this.onSettings});
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;

  @override
  State<TrackingSettingsScreen> createState() =>
      _TrackingSettingsScreenState();
}

class _TrackingSettingsScreenState extends State<TrackingSettingsScreen> {
  late AppSettings _s;
  Map<String, dynamic> _t = {};
  String _msg = '';
  bool _busy = false;

  static const _appOAuthRedirect = 'https://ganime.pages.dev/app-oauth';
  static const _relayUrl = 'https://ganime-relay.gp237372.workers.dev';

  /// AniList client for the APP. If you get "redirect_uri mismatch", create
  /// a second client at anilist.co/settings/developer with redirect
  /// https://ganime.pages.dev/app-oauth?provider=anilist and paste its id
  /// here (the website's client keeps its own redirect, website stays fine).
  static const _anilistAppClientId = '54686';

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _reload();
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  Future<void> _reload() async {
    _t = await Store.tracker();
    if (mounted) setState(() {});
  }

  bool get _alConnected =>
      (_t['anilistToken'] as String?)?.isNotEmpty == true;
  bool get _skConnected =>
      (_t['simklToken'] as String?)?.isNotEmpty == true;
  bool get _malConnected =>
      (_t['malToken'] as String?)?.isNotEmpty == true;

  String get _alName => (_t['anilistUsername'] as String?) ??
      (_alConnected ? 'Connected' : 'Not connected');
  String get _skName => (_t['simklUsername'] as String?) ??
      (_skConnected ? 'Connected' : 'Not connected');
  String get _malName => (_t['malUsername'] as String?)?.isNotEmpty == true
      ? "@${_t['malUsername']}"
      : (_malConnected ? 'Connected' : 'Not connected');

  Future<void> _disconnect(String pkey, String title, List<String> keys) async {
    // Trackers are per-device (never cloud-synced): disconnect = just
    // remove the local keys. Nothing to tombstone, nothing to propagate.
    final m = await Store.tracker();
    for (final k in keys) {
      m.remove(k);
    }
    m.remove('${pkey}DisconnectedAt'); // legacy tombstone, no longer used
    await Store.saveTracker(m);
    _msg = '$title disconnected.';
    await _reload();
  }

  // ---- OAuth link helpers ----

  Map<String, String> _frag(Uri u) {
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
  Future<Uri?> _waitLink(String provider, String state,
      {bool fragment = false}) async {
    final links = AppLinks();
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
      return await links.uriLinkStream.firstWhere(matches);
    } on StateError {
      return null;
    }
  }

  // ---- One-tap connect handlers ----

  Future<void> _connectAnilist() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = 'Waiting for AniList…';
    });
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
      if (!ok) throw Exception('Could not open browser');
      // Code flow: AniList redirects with ?code=...&state=... (query, not fragment).
      final cb = await _waitLink('anilist', state);
      final code = cb?.queryParameters['code'];
      if (code == null) {
        setState(() => _msg = 'AniList login cancelled or timed out.');
        return;
      }
      final data = await OAuthService.exchangeAnilist(code);
      final tok = data['access_token'] as String;
      final v = await Trackers.anilistViewer(tok);
      final m = await Store.tracker();
      m['anilistToken'] = tok;
      m['anilistUserId'] = (v['id'] ?? '').toString();
      m['anilistUsername'] = (v['name'] ?? '').toString();
      await Store.saveTracker(m);
      _msg = 'AniList connected.';
      await _reload();
    } catch (e) {
      _msg = 'AniList connect failed: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectSimkl() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = 'Waiting for Simkl…';
    });
    try {
      final verifier = OAuthService.generateVerifier();
      final challenge = OAuthService.s256Challenge(verifier);
      final state = OAuthService.generateState();
      final ok = await launchUrl(
          Uri.parse(OAuthService.simklAuthorizeUrl(challenge, state)),
          mode: LaunchMode.inAppBrowserView);
      if (!ok) throw Exception('Could not open browser');
      final cb = await _waitLink('simkl', state);
      final code = cb?.queryParameters['code'];
      if (code == null) {
        setState(() => _msg = 'Simkl login cancelled or timed out.');
        return;
      }
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
          m['simklUsername'] = (user['name'] ?? user['username'] ?? '').toString();
        }
      } catch (_) {}
      await Store.saveTracker(m);
      _msg = 'Simkl connected.';
      await _reload();
    } catch (e) {
      _msg = 'Simkl connect failed: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectMal() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = 'Waiting for MAL…';
    });
    try {
      final verifier = OAuthService.generateVerifier();
      final state = OAuthService.generateState();
      final ok = await launchUrl(
          Uri.parse(OAuthService.malAuthorizeUrl(verifier, state)),
          mode: LaunchMode.inAppBrowserView);
      if (!ok) throw Exception('Could not open browser');
      final cb = await _waitLink('mal', state);
      final code = cb?.queryParameters['code'];
      if (code == null) {
        setState(() => _msg = 'MAL login cancelled or timed out.');
        return;
      }
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
      _msg = 'MAL connected.';
      await _reload();
    } catch (e) {
      _msg = 'MAL connect failed: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- UI ----

  Widget _dot(bool c) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c ? Theme.of(context).colorScheme.primary : const Color(0xFF5B5B66),
          boxShadow: c
              ? [
                  BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.8),
                      blurRadius: 8)
                ]
              : null,
        ),
      );

  /// Website parity (openTrackerManage): a connected tracker opens a modal
  /// with "Connected as @user — sync is live." and Reconnect / Disconnect /
  /// Close buttons (MAL also gets Sync / Update). Replaces the old inline
  /// expand which only offered Disconnect.
  Future<void> _openManage({
    required String provider,
    required String name,
    required String username,
    required VoidCallback onReconnect,
    required VoidCallback onDisconnect,
    VoidCallback? onSyncUpdate,
  }) async {
    final who = username.isNotEmpty ? username : 'Connected';
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: GaColors.of(dCtx).card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                style:
                    const TextStyle(color: gaGrey, fontSize: 14),
                children: [
                  const TextSpan(text: 'Connected as '),
                  TextSpan(
                      text: who,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' — sync is live.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (onSyncUpdate != null) ...[
              OutlinedButton(
                onPressed: () {
                  Navigator.of(dCtx).pop();
                  onSyncUpdate();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: gaCardBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Sync / Update'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              onPressed: () {
                Navigator.of(dCtx).pop();
                onReconnect();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: gaCardBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Reconnect'),
            ),
            const SizedBox(height: 10),
            gaGreenButton(
              context: dCtx,
              label: 'Disconnect',
              onPressed: () {
                Navigator.of(dCtx).pop();
                onDisconnect();
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: gaCardBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required String name,
    required String username,
    required bool connected,
    required String key,
    required VoidCallback onConnect,
    required VoidCallback onReconnect,
    required VoidCallback onDisconnect,
    VoidCallback? onSyncUpdate,
  }) {
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _dot(connected),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(username,
              style: const TextStyle(color: gaGrey, fontSize: 12.5)),
          const SizedBox(height: 12),
          if (!connected)
            gaGreenButton(
              context: context,
              label: 'Connect with $name',
              onPressed: _busy ? null : onConnect,
            )
          else
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _openManage(
                        provider: key,
                        name: name,
                        username: username,
                        onReconnect: onReconnect,
                        onDisconnect: onDisconnect,
                        onSyncUpdate: onSyncUpdate,
                      ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: gaCardBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: const Text('Manage'),
            ),
        ],
      ),
    );
  }

  Widget _sourceCard() {
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONTINUE WATCHING DATA SOURCE',
              style: TextStyle(
                  color: gaGrey,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          _srcTile('GANime Cloud', 'Cross-device sync store', 'cloud'),
          const SizedBox(height: 8),
          _srcTile('Tracked Sync', 'AniList / MAL / Simkl', 'tracked'),
        ],
      ),
    );
  }

  Widget _srcTile(String title, String sub, String value) {
    final sel = _s.continueWatchingSource == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _save(_s.copyWith(continueWatchingSource: value)),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF26262B) : const Color(0xFF1B1B1F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: sel ? Colors.white : gaCardBorder,
                width: sel ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(sub,
                        style: const TextStyle(color: gaGrey, fontSize: 12.5)),
                  ],
                ),
              ),
              if (sel)
                const Icon(Icons.check, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Tracking',
      children: [
        _card(
          name: 'AniList',
          username: _alName,
          connected: _alConnected,
          key: 'anilist',
          onConnect: _connectAnilist,
          onReconnect: _connectAnilist,
          onDisconnect: () => _disconnect('anilist', 'AniList', const [
            'anilistToken',
            'anilistUserId',
            'anilistUsername',
          ]),
        ),
        const SizedBox(height: 10),
        _card(
          name: 'MyAnimeList',
          username: _malName,
          connected: _malConnected,
          key: 'mal',
          onConnect: _connectMal,
          onReconnect: _connectMal,
          onSyncUpdate: _connectMal,
          onDisconnect: () => _disconnect('mal', 'MyAnimeList', const [
            'malClientId',
            'malToken',
            'malRefreshToken',
            'malUsername',
          ]),
        ),
        const SizedBox(height: 10),
        _card(
          name: 'Simkl',
          username: _skName,
          connected: _skConnected,
          key: 'simkl',
          onConnect: _connectSimkl,
          onReconnect: _connectSimkl,
          onDisconnect: () => _disconnect('simkl', 'Simkl', const [
            'simklClientId',
            'simklToken',
            'simklRefreshToken',
            'simklExpiresAt',
            'simklUsername',
          ]),
        ),
        const SizedBox(height: 18),
        if (_msg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_msg,
                style: const TextStyle(color: gaGrey, fontSize: 12.5)),
          ),
        gaSectionLabel('Continue Watching Data Source'),
        const SizedBox(height: 10),
        _sourceCard(),
      ],
    );
  }
}
