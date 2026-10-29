// Addon settings sub-screen (website Addons screen parity).
// User-installed ONLY: the app ships with NO stream sources and recommends none.
// Never name stream providers/hosts here — the user pastes a Stremio
// manifest URL they found themselves.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../store.dart';
import '../../models.dart';
import '../../services/addons.dart';
import 'settings_shell.dart';

class AddonSettingsScreen extends StatefulWidget {
  const AddonSettingsScreen({super.key, required this.profileId});
  final String profileId;

  @override
  State<AddonSettingsScreen> createState() => _AddonSettingsScreenState();
}

class _AddonSettingsScreenState extends State<AddonSettingsScreen> {
  List<AddonRecord> _addons = [];
  final _addonCtrl = TextEditingController();
  String _msg = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addonCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await Store.addons(widget.profileId);
    if (!mounted) return;
    setState(() => _addons = list);
  }

  Future<void> _persist() =>
      Store.saveAddons(widget.profileId, _addons);

  Future<void> _install() async {
    if (_busy) return;
    final input = _addonCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _msg = 'Paste a manifest URL first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final rec = await AddonsService.fetchManifest(input);
      if (_addons.any((a) => a.manifestUrl == rec.manifestUrl)) {
        _msg = 'Addon already installed.';
      } else {
        _addons = [..._addons, rec];
        await _persist();
        _addonCtrl.clear();
        _msg = 'Installed: ${rec.name}';
      }
    } catch (e) {
      _msg = 'Addon install failed: $e';
    }
    _busy = false;
    if (mounted) setState(() {});
  }

  Future<void> _refresh(AddonRecord a, int i) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fresh = await AddonsService.fetchManifest(a.manifestUrl);
      _addons[i] = AddonRecord(
        manifestUrl: a.manifestUrl,
        baseUrl: a.baseUrl,
        id: a.id,
        name: fresh.name,
        version: fresh.version,
        addedAt: a.addedAt,
        enabled: a.enabled,
        description: fresh.description,
        logoUrl: fresh.logoUrl,
        resources: fresh.resources,
      );
      await _persist();
      _msg = 'Refreshed: ${fresh.name}';
    } catch (e) {
      _msg = 'Refresh failed: $e';
    }
    _busy = false;
    if (mounted) setState(() {});
  }

  Future<void> _configure(AddonRecord a) async {
    await launchUrl(
      Uri.parse(a.baseUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _confirmDelete(AddonRecord a, int i) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: gaCard,
        title: const Text('Remove addon?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text(a.name, style: const TextStyle(color: gaGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: gaGrey)),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent),
            onPressed: () async {
              _addons = List.of(_addons)..removeAt(i);
              await _persist();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;
              setState(() => _msg = 'Removed: ${a.name}');
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _logo(AddonRecord a) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: a.logoUrl.isNotEmpty
            ? Image.network(
                a.logoUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _logoFallback(),
              )
            : _logoFallback(),
      );

  Widget _logoFallback() => Container(
        width: 56,
        height: 56,
        color: gaFieldFill,
        child: const Icon(Icons.extension, color: gaGrey),
      );

  Widget _sqBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: gaCardBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            color: enabled ? Colors.white : gaGreyDark, size: 20),
      ),
    );
  }

  String _resLabel(String r) {
    const labels = {
      'stream': 'Stream',
      'catalog': 'Catalog',
      'meta': 'Meta',
      'subtitles': 'Subtitles',
      'addon_catalog': 'Addon Catalog',
    };
    final hit = labels[r];
    if (hit != null) return hit;
    if (r.isEmpty) return r;
    return r[0].toUpperCase() + r.substring(1);
  }

  Widget _tag(String label) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: gaFieldFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gaCardBorder),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: gaGrey)),
      );

  Widget _addonCard(AddonRecord a, int i) {
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _logo(a),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    if (a.version.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: gaFieldFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: gaCardBorder),
                        ),
                        child: Text('v${a.version}',
                            style: const TextStyle(
                                color: gaGrey, fontSize: 11)),
                      ),
                  ],
                ),
              ),
              Switch(
                value: a.enabled,
                onChanged: (v) async {
                  _addons[i] = a.copyWith(enabled: v);
                  await _persist();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _sqBtn(Icons.arrow_upward, i > 0, () async {
                final l = List.of(_addons);
                final t = l[i - 1];
                l[i - 1] = l[i];
                l[i] = t;
                _addons = l;
                await _persist();
                if (mounted) setState(() {});
              }),
              const SizedBox(width: 8),
              _sqBtn(Icons.arrow_downward, i < _addons.length - 1,
                  () async {
                final l = List.of(_addons);
                final t = l[i + 1];
                l[i + 1] = l[i];
                l[i] = t;
                _addons = l;
                await _persist();
                if (mounted) setState(() {});
              }),
              const SizedBox(width: 8),
              _sqBtn(Icons.refresh, true, () => _refresh(a, i)),
              const SizedBox(width: 8),
              _sqBtn(Icons.settings, true, () => _configure(a)),
              const SizedBox(width: 8),
              _sqBtn(Icons.delete_outline, true,
                  () => _confirmDelete(a, i)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(a.enabled ? 'Active' : 'Disabled'),
              for (final r in a.resources) _tag(_resLabel(r)),
            ],
          ),
          if (a.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(a.description,
                  style: const TextStyle(
                      color: gaGrey, fontSize: 13, height: 1.5)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(a.manifestUrl,
                style: const TextStyle(color: gaGreyDark, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Addons',
      children: [
        gaSectionLabel('Install Addon'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: gaTextField(
                controller: _addonCtrl,
                hint: 'https://example.com/manifest.json',
                keyboardType: TextInputType.url,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: _busy ? null : _install,
                style: ElevatedButton.styleFrom(
                  backgroundColor: gaGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Add Addon',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        GACard(
          child: const Text(
            'This app ships with NO stream sources and recommends none. Paste a Stremio manifest URL you found yourself.',
            style: TextStyle(color: gaGrey, fontSize: 13),
          ),
        ),
        gaSectionLabel('Installed Addons — ${_addons.length}'),
        for (int i = 0; i < _addons.length; i++) _addonCard(_addons[i], i),
        gaMsg(_msg),
      ],
    );
  }
}
