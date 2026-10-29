// Settings > Account sub-screen (website parity).
// Profiles (always visible) + Firebase on-device config / signed-in account view.
import 'package:flutter/material.dart';
import '../../store.dart';
import '../../models.dart';
import '../../services/firebase_sync.dart';
import 'settings_shell.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen(
      {super.key,
      required this.account,
      required this.profileId,
      required this.settings,
      required this.onProfile,
      required this.firebase});
  final String account;
  final String profileId;
  final AppSettings settings;
  final ValueChanged<String> onProfile;
  final FirebaseSync firebase;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  List<Profile> _profiles = [];
  final _fbApiCtrl = TextEditingController();
  final _fbProjectCtrl = TextEditingController();
  final _fbEmailCtrl = TextEditingController();
  final _fbPassCtrl = TextEditingController();
  String _msg = '';
  String? _email;
  String? _lastSyncIso;
  bool _busy = false;
  bool _advancedOpen = false; // Firebase project config lives here.

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _fbApiCtrl.dispose();
    _fbProjectCtrl.dispose();
    _fbEmailCtrl.dispose();
    _fbPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _profiles = await Store.profiles(widget.account);
    final config = await Store.firebaseConfig();
    _fbApiCtrl.text = (config['apiKey'] as String?) ?? '';
    _fbProjectCtrl.text = (config['projectId'] as String?) ?? '';
    _email = await widget.firebase.savedEmail();
    _lastSyncIso = await Store.lastSync();
    if (mounted) setState(() {});
  }

  String _fmt(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    } catch (_) {
      return iso;
    }
  }

  String _syncText() => _lastSyncIso == null
      ? 'Never synced yet'
      : 'Last synced ${_fmt(_lastSyncIso!)} · Cloud copy updated';

  Future<void> _doSync() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final profiles = await Store.profiles(widget.account);
      final watched = await Store.allWatched(widget.profileId);
      final lib = await Store.localLibrary(widget.profileId);
      final ads = await Store.addons(widget.profileId);
      final tombs = await Store.tombstones();
      await widget.firebase.push(
        account: widget.account,
        settings: widget.settings,
        profiles: profiles,
        watched: watched,
        localLibrary: lib,
        addons: ads,
        tombstones: tombs,
      );
      _lastSyncIso = await Store.lastSync();
      _msg = 'Sync Now pushed to users/{uid}.';
    } catch (e) {
      _msg = 'Sync failed: $e';
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await widget.firebase.saveConfig(
          _fbApiCtrl.text.trim(), _fbProjectCtrl.text.trim());
      await widget.firebase
          .signIn(_fbEmailCtrl.text.trim(), _fbPassCtrl.text);
      _email = _fbEmailCtrl.text.trim();
      _msg = 'Firebase signed in.';
    } catch (e) {
      _msg = 'Firebase sign-in failed: $e';
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await widget.firebase.saveConfig(
          _fbApiCtrl.text.trim(), _fbProjectCtrl.text.trim());
      await widget.firebase
          .signUp(_fbEmailCtrl.text.trim(), _fbPassCtrl.text);
      _email = _fbEmailCtrl.text.trim();
      _msg = 'Firebase account created + signed in.';
    } catch (e) {
      _msg = 'Firebase sign-up failed: $e';
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Widget _profileCard(Profile p) {
    return GACard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Store.setActiveProfile(widget.account, p.id);
          widget.onProfile(p.id);
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
              ),
              if (p.id == widget.profileId)
                Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addProfileCard() {
    return GACard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final ps = await Store.profiles(widget.account);
          ps.add(Profile(
            id: 'p${DateTime.now().millisecondsSinceEpoch}',
            name: 'Profile ${ps.length + 1}',
          ));
          await Store.saveProfiles(widget.account, ps);
          if (mounted) setState(() => _profiles = ps);
        },
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('Add profile',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Account',
      children: [
        gaSectionLabel('Profiles'),
        for (final p in _profiles) _profileCard(p),
        _addProfileCard(),
        if (widget.firebase.signedIn) ...[
          gaSectionLabel('Account'),
          GACard(
            child: Row(
              children: [
                const Text('Status',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(_email ?? 'Signed in',
                    style:
                        const TextStyle(color: gaGrey, fontSize: 14)),
              ],
            ),
          ),
          GACard(
            child: Row(
              children: [
                const Text('Cloud Sync',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Expanded(
                  child: Text(_syncText(),
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(color: gaGrey, fontSize: 13)),
                ),
              ],
            ),
          ),
          gaWhiteButton(
              label: 'Sync Now', onPressed: _busy ? null : _doSync),
          gaWhiteButton(
            label: 'Sign Out',
            onPressed: () {
              widget.firebase.signOut();
              setState(() {
                _email = null;
                _msg = 'Signed out.';
              });
            },
          ),
          gaMsg(_msg),
        ] else ...[
          gaSectionLabel('Firebase sync (optional)'),
          // Advanced (collapsed by default): the project-config fields and
          // the developer note live here; sign-in stays one tap away.
          InkWell(
            onTap: () =>
                setState(() => _advancedOpen = !_advancedOpen),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Advanced',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  Icon(
                      _advancedOpen
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          if (_advancedOpen) ...[
            const GACard(
              child: Text(
                'Enter YOUR Firebase project config here on-device. It is never written into the repo. One doc: users/{uid}.',
                style: TextStyle(color: gaGrey, fontSize: 13),
              ),
            ),
            gaTextField(
                context: context,
                controller: _fbApiCtrl,
                hint: 'Firebase apiKey'),
            gaTextField(
                context: context,
                controller: _fbProjectCtrl,
                hint: 'Firebase projectId'),
          ],
          gaTextField(context: context, 
              controller: _fbEmailCtrl,
              hint: 'Email',
              keyboardType: TextInputType.emailAddress),
          gaTextField(context: context, 
              controller: _fbPassCtrl, hint: 'Password', obscure: true),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _signUp,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Create account'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          gaWhiteButton(
              label: 'Sync Now', onPressed: _busy ? null : _doSync),
          gaMsg(_msg),
        ],
      ],
    );
  }
}
