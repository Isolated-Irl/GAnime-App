// Settings > Account sub-screen — website parity (ganime.pages.dev/#profile,
// pageAccountTab): Status row + Cloud Sync card + Sync Now + Sign Out when
// signed in; guest view with true state + Sign In / Create Account + Reset.
// Profiles live in the Who's watching? picker (top-bar avatar), like the web.
import 'package:flutter/material.dart';
import '../../store.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../services/firebase_sync.dart';
import 'settings_shell.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen(
      {super.key,
      required this.account,
      required this.profileId,
      required this.settings,
      required this.onBackToGate,
      required this.firebase});
  final String account;
  final String profileId;
  final AppSettings settings;

  /// Website parity: the web's account tab returns to the auth gate on
  /// Sign Out (signed-in) and on Sign In / Create Account (guest).
  /// Pops settings routes and swaps the boot phase to the gate.
  final VoidCallback onBackToGate;
  final FirebaseSync firebase;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  String _msg = '';
  String? _email;
  Map<String, dynamic>? _syncRecord;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _email = await widget.firebase.savedEmail();
    _syncRecord = await Store.syncRecord();
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

  /// Website parity: pageAccountTab's syncText —
  /// `Never synced yet` | `Last synced <date> · <detail>`
  /// | `Last sync: <status> — <date> · <detail>` | `Error: <lastError>`.
  String _syncText() {
    final r = _syncRecord;
    if (r == null) return 'Never synced yet';
    final status = (r['status'] as String?) ?? '';
    final detail = (r['detail'] as String?) ?? '';
    if (status == 'error') {
      return detail.isNotEmpty ? 'Error: $detail' : 'Error syncing';
    }
    final at = (r['at'] as String?) ?? '';
    final when = at.isNotEmpty ? _fmt(at) : '';
    final base = status == 'synced'
        ? 'Last synced $when'
        : 'Last sync: $status — $when';
    return detail.isNotEmpty ? '$base · $detail' : base;
  }

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
      _syncRecord = await Store.syncRecord();
      _msg = 'Sync Now pushed to users/{uid}.';
      // Pull the merged result back — the cloud now has the union of
      // local + remote profiles, but the device still has only the old list.
      try {
        final remote = await widget.firebase.pullRaw();
        if (remote != null) {
          final remoteProfiles = (remote['profiles'] as List?) ?? [];
          final profiles = remoteProfiles
              .map((e) => Profile.fromJson(e as Map<String, dynamic>))
              .toList();
          if (profiles.isNotEmpty) {
            await Store.saveProfiles(widget.account, profiles);
          }
        }
      } catch (_) {
        // Pull failed — push already succeeded, profiles will merge on next sync.
      }
    } catch (e) {
      final detail = '$e'.replaceFirst('Exception: ', '');
      _msg = 'Sync failed: $detail';
      await Store.setSyncRecord(
        at: DateTime.now().toIso8601String(),
        status: 'error',
        detail: detail,
      );
      _syncRecord = await Store.syncRecord();
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  /// Website parity: Sign Out clears the session and shows the gate.
  Future<void> _signOut() async {
    await widget.firebase.signOut();
    await Store.setGuest(false);
    widget.onBackToGate();
  }

  /// Website parity: a guest has nothing to sign out of — this clears the
  /// guest flag and shows the gate. It never wipes profiles/data.
  Future<void> _toGate() async {
    await Store.setGuest(false);
    widget.onBackToGate();
  }

  /// Website parity: wipeDeviceData() — the ONLY wipe, behind a confirm.
  /// Guests only (signed-in users have a cloud copy; a local reset option
  /// would only confuse). Sign Out deliberately does NOT do this.
  Future<void> _confirmWipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: GaColors.of(dCtx).card,
        title: const Text('Reset all local data?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your profiles, installed addons, watch history, and local library on this device.',
          style: TextStyle(color: gaGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: gaGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Reset',
                style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.firebase.signOut();
    await Store.wipeAll();
    widget.onBackToGate();
  }

  /// Website parity: sInfo(label, value) — label left, muted value right.
  Widget _infoCard(String label, String value) {
    return GACard(
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(color: gaGrey, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Full-width white button without the list padding (for use inside cards).
  Widget _whiteBtn(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  /// Website parity: the Sync Now button lives INSIDE the Cloud Sync group.
  Widget _cloudSyncCard() {
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Cloud Sync',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_syncText(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: gaGrey, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _whiteBtn('Sync Now', _doSync),
        ],
      ),
    );
  }

  /// Website parity: guests see only the red Reset button (btn-secondary).
  Widget _resetButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _confirmWipe,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF87171),
            side: BorderSide(
                color: const Color(0xFFF87171).withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          child: const Text('Reset All Local Data'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // GACard carries a 12px bottom margin; the website's account tab uses
    // a 14px rhythm between groups.
    const gap = SizedBox(height: 2);
    if (widget.firebase.signedIn) {
      return GASubPage(
        title: 'Account',
        children: [
          _infoCard('Status', _email ?? 'Signed in'),
          gap,
          _cloudSyncCard(),
          gap,
          gaWhiteButton(
              label: 'Sign Out',
              onPressed: _busy ? null : () => _signOut()),
          gaMsg(_msg),
        ],
      );
    }
    // Guest view — website parity: true state, no Sign Out (a guest has
    // nothing to sign out of), Sign In / Create Account returns to the
    // gate, Reset is guests-only and confirmed.
    return GASubPage(
      title: 'Account',
      children: [
        _infoCard('Status', 'Guest (Local Only)'),
        gap,
        _infoCard('Cloud Sync',
            'Off — guest mode does not sync. Sign in to sync.'),
        gap,
        gaWhiteButton(
            label: 'Sign In / Create Account',
            onPressed: _busy ? null : () => _toGate()),
        _resetButton(),
        gaMsg(_msg),
      ],
    );
  }
}
