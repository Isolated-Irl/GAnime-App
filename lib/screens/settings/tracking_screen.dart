// Settings > Tracking sub-screen (website parity).
// Tracker connection cards (AniList / MAL / Simkl) with manage forms,
// plus the Continue Watching data source selector.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../store.dart';
import '../../models.dart';
import '../../services/trackers.dart';
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
  final _alToken = TextEditingController();
  final _skClient = TextEditingController();
  final _skCode = TextEditingController();
  final _malUser = TextEditingController();
  final _malClient = TextEditingController();
  String _msg = '';
  // Website parity (Config.OAUTH): baked-in client IDs for one-tap connect.
  // Public IDs from the website's public config.js — safe to ship.
  // Note: _anilistClientId is already defined above (line 33).
  static const _malClientId = 'f15fbfc461e31b1674c0747f5e680f01';
  static const _simklClientId =
      '49dfaf44602c7464026066ff52eb2e4fb797f26a136a2107c250e5d9f73f8a7b';
  String? _open;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _reload();
  }

  @override
  void dispose() {
    _alToken.dispose();
    _skClient.dispose();
    _skCode.dispose();
    _malUser.dispose();
    _malClient.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  Future<void> _reload() async {
    _t = await Store.tracker();
    _alToken.text = (_t['anilistToken'] as String?) ?? '';
    _skClient.text = (_t['simklClientId'] as String?) ?? '';
    _malUser.text = (_t['malUsername'] as String?) ?? '';
    _malClient.text = (_t['malClientId'] as String?) ?? '';
    if (mounted) setState(() {});
  }

  bool get _alConnected =>
      (_t['anilistToken'] as String?)?.isNotEmpty == true;
  bool get _skConnected =>
      (_t['simklToken'] as String?)?.isNotEmpty == true;
  bool get _malConnected =>
      (_t['malUsername'] as String?)?.isNotEmpty == true;

  String get _alName => (_t['anilistUsername'] as String?) ??
      (_alConnected ? 'Connected' : 'Not connected');
  String get _skName => (_t['simklUsername'] as String?) ??
      (_skConnected ? 'Connected' : 'Not connected');
  String get _malName =>
      _malConnected ? "@${_t['malUsername']}" : 'Not connected';

  // Website `.tsc-dot`: 9px, top-right of the name row, green glow when on.
  Widget _dot(bool c) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c ? Theme.of(context).colorScheme.primary : const Color(0xFF5B5B66),
          boxShadow: c
              ? [
                  BoxShadow(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.8),
                      blurRadius: 8)
                ]
              : null,
        ),
      );

  Widget _card({
    required String name,
    required String username,
    required bool connected,
    required String key,
  }) {
    final open = _open == key;
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Website `.tsc-top`: name left, dot top-right (space-between,
          // top-aligned), state text below.
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () =>
                  setState(() => _open = open ? null : key),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: gaCardBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: const Text('Manage'),
            ),
          ),
          if (open) ...[
            const SizedBox(height: 12),
            if (key == 'anilist')
              _anilistForm()
            else if (key == 'simkl')
              _simklForm()
            else
              _malForm(),
          ],
        ],
      ),
    );
  }

  // ---- AniList manage form ----
  // Website parity: the client ID is baked into the public website
  // config (Config.OAUTH.ANILIST_CLIENT_ID), so one-click connect works
  // with no form. Same here — implicit grant, response_type=token shows
  // the token on AniList's PIN page for pasting.
  static const _anilistClientId = '54686';

  Future<void> _saveAnilist() async {
    var tok = _alToken.text.trim();
    if (tok.isEmpty) {
      setState(() => _msg = 'Paste your AniList token first.');
      return;
    }
    // Website parity (anilist.js verifyToken): accept a bare JWT or a
    // pasted URL whose fragment carries it; reject authorization codes
    // with a helpful explanation.
    final frag = RegExp(r'access_token=([^&\s]+)').firstMatch(tok);
    if (frag != null) tok = Uri.decodeComponent(frag.group(1)!);
    if (RegExp(r'^[0-9a-f]{32,}$', caseSensitive: false).hasMatch(tok) ||
        !tok.contains('.')) {
      setState(() => _msg =
          'That looks like an authorization code, not a token. Tap "Connect with AniList" and approve again — the page shows the long token (starts with eyJ).');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final v = await Trackers.anilistViewer(tok);
      final m = await Store.tracker();
      m['anilistToken'] = tok;
      m['anilistUserId'] = v['id'];
      m['anilistUsername'] = v['name'];
      await Store.saveTracker(m);
      _msg = "AniList connected: ${v['name']}";
      await _reload();
    } catch (e) {
      _msg = 'AniList connect failed: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(String label, List<String> keys) async {
    final m = await Store.tracker();
    for (final k in keys) {
      m.remove(k);
    }
    await Store.saveTracker(m);
    _msg = '$label disconnected.';
    await _reload();
  }

  Widget _anilistForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Website parity (connectAnilistOneClick): one tap opens AniList's
        // approval page with our client ID; the PIN page shows the token
        // to paste below. No client-ID form needed.
        gaGreenButton(
          context: context,
          label: 'Connect with AniList',
          onPressed: _busy
              ? null
              : () => launchUrl(
                    Uri.parse(
                        'https://anilist.co/api/v2/oauth/authorize?client_id=$_anilistClientId&response_type=token'),
                    mode: LaunchMode.externalApplication,
                  ),
        ),
        const SizedBox(height: 12),
        gaTextField(context: context,
            controller: _alToken,
            hint: 'Paste the token from AniList'),
        const SizedBox(height: 12),
        gaGreenButton(context: context, 
            label: 'Save AniList token',
            onPressed: _busy ? null : _saveAnilist),
        if (_alConnected)
          Center(
            child: TextButton(
              onPressed: () => _disconnect('AniList', const [
                'anilistToken',
                'anilistUserId',
                'anilistUsername'
              ]),
              child: const Text('Disconnect AniList',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  // ---- Simkl manage form ----
  Future<void> _simklConnect() async {
    if (_busy) return;
    final clientId = _skClient.text.trim();
    if (clientId.isEmpty) {
      setState(() => _msg = 'Enter your Simkl client id first.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final code = _skCode.text.trim();
      if (code.isEmpty) {
        final pin = await Trackers.simklStartPin(clientId);
        _msg =
            "Simkl PIN: user code ${pin['user_code']}. Enter it on the Simkl site, then paste the code above and tap again.";
      } else {
        final res = await Trackers.simklCheckPin(clientId, code);
        final m = await Store.tracker();
        m['simklClientId'] = clientId;
        m['simklToken'] = res['access_token'];
        await Store.saveTracker(m);
        _msg = 'Simkl connected.';
        await _reload();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _msg = 'Simkl failed: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _simklForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Website parity (connectSimklOneClick): one tap fills the baked-in
        // client ID and starts the PIN flow — no manual ID entry.
        gaGreenButton(
          context: context,
          label: 'Connect with Simkl',
          onPressed: _busy
              ? null
              : () {
                  _skClient.text = _simklClientId;
                  _simklConnect();
                },
        ),
        const SizedBox(height: 12),
        gaTextField(context: context, controller: _skClient, hint: 'Simkl client id'),
        gaTextField(context: context, 
            controller: _skCode,
            hint: 'Simkl PIN user code (optional)'),
        gaGreenButton(context: context, 
            label: 'Simkl PIN / connect',
            onPressed: _busy ? null : _simklConnect),
        if (_skConnected)
          Center(
            child: TextButton(
              onPressed: () => _disconnect('Simkl', const [
                'simklClientId',
                'simklToken',
                'simklUsername'
              ]),
              child: const Text('Disconnect Simkl',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  // ---- MAL manage form ----
  Future<void> _saveMal() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final m = await Store.tracker();
      m['malUsername'] = _malUser.text.trim();
      m['malClientId'] = _malClient.text.trim();
      await Store.saveTracker(m);
      _msg = 'MAL saved (read-only list).';
      await _reload();
    } catch (e) {
      _msg = 'MAL save failed: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _malForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Website parity (connectMalOneClick): one tap fills the baked-in
        // client ID — user just enters username and saves.
        gaGreenButton(
          context: context,
          label: 'Connect with MAL',
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _malClient.text = _malClientId;
                    _msg = 'Client ID filled — enter your MAL username and tap Save.';
                  });
                },
        ),
        const SizedBox(height: 12),
        gaTextField(context: context, controller: _malUser, hint: 'MAL username'),
        gaTextField(context: context, controller: _malClient, hint: 'MAL client id'),
        gaGreenButton(context: context, 
            label: 'Save MAL (read-only)',
            onPressed: _busy ? null : _saveMal),
        if (_malConnected)
          Center(
            child: TextButton(
              onPressed: () =>
                  _disconnect('MAL', const ['malUsername', 'malClientId']),
              child: const Text('Disconnect MAL',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  // ---- Continue Watching data source ----
  Widget _sourceCard(
      {required String value,
      required String title,
      required String subtitle}) {
    final selected = _s.continueWatchingSource == value;
    return GACard(
      padding: EdgeInsets.zero,
      border: selected
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
          : Border.all(color: gaCardBorder),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            _save(_s.copyWith(continueWatchingSource: value)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: gaGrey, fontSize: 13)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
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
            key: 'anilist'),
        _card(
            name: 'MyAnimeList',
            username: _malName,
            connected: _malConnected,
            key: 'mal'),
        _card(
            name: 'Simkl',
            username: _skName,
            connected: _skConnected,
            key: 'simkl'),
        gaSectionLabel('Continue watching data source'),
        _sourceCard(
            value: 'cloud',
            title: 'GAnime Cloud',
            subtitle: 'Cross-device sync store'),
        _sourceCard(
            value: 'tracked',
            title: 'Tracked Sync',
            subtitle: 'AniList / MAL / Simkl'),
        gaMsg(_msg),
      ],
    );
  }
}
