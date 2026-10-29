// Details + Episodes — website mobile-parity layout.
// Banner with back button, chips, collapsible synopsis, Play Ep N pill,
// library / mark-all-watched / trailer action row, Watching Progress card
// with tracking sheet, episode filter row (Filter menu + All + ranges),
// and Detailed / Minimum episode layouts (persisted in AppSettings).
// Episodes come from Kitsu; watched + saved state is local per profile.
// Tapping an episode opens the stream picker, then the player.
// If no addon is installed, streams are empty and the player screen
// explains that — the app never invents a stream source.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/episodes.dart';
import '../services/kitsu.dart';
import '../services/addons.dart';
import '../services/trackers.dart';
import '../store.dart';
import 'player.dart';
import '../widgets/skeletons.dart';

class DetailsScreen extends StatefulWidget {
  final Anime anime;
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime anime, int episode)? onMarkWatched;
  const DetailsScreen({
    super.key,
    required this.anime,
    required this.profileId,
    required this.settings,
    this.onMarkWatched,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

/// Library menu entries, mirroring the website's status menu.
/// Stored as the app's status codes.
const _libMenu = [
  ('Watching', 'CURRENT'),
  ('Plan to Watch', 'PLANNING'),
  ('Completed', 'COMPLETED'),
  ('On Hold', 'PAUSED'),
  ('Dropped', 'DROPPED'),
];

String _libStatusName(String code) {
  for (final e in _libMenu) {
    if (e.$2 == code) return e.$1;
  }
  return code;
}

class _EpRange {
  final int from;
  final int to;
  const _EpRange(this.from, this.to);
  int get count => to - from + 1;
  String get label => '$from - $to';
}

class _DetailsScreenState extends State<DetailsScreen> {
  List<EpisodeInfo> _episodes = [];
  Set<int> _watched = {};
  Set<int> _saved = {};
  bool _loading = true;
  String? _error;
  bool _synopsisExpanded = false;
  late String _layout; // 'detailed' | 'minimum'
  int? _rangeFrom; // null = All
  bool _filterOpen = false;
  String? _libStatus; // app status code, null = not in library

  static const _card = Color(0xFF222222);

  @override
  void initState() {
    super.initState();
    _layout = widget.settings.episodeLayout == 'minimum'
        ? 'minimum'
        : 'detailed';
    _load();
  }

  bool get _isMovie => widget.anime.format == 'MOVIE';

  int get _total {
    if (_isMovie) return 1;
    if (_episodes.isNotEmpty) return _episodes.length;
    return widget.anime.episodes ?? 0;
  }

  /// First unwatched episode (website logic); wraps to 1 when all watched.
  int get _nextEp {
    final total = _total;
    var n = 1;
    while (n <= total && _watched.contains(n)) {
      n++;
    }
    return n > total ? 1 : n;
  }

  int get _watchedCount {
    final total = _total;
    return _watched.where((n) => n >= 1 && n <= total).length;
  }

  bool get _allWatched =>
      _total > 0 &&
      List.generate(_total, (i) => i + 1).every(_watched.contains);

  Future<void> _load() async {
    try {
      final eps = await EpisodesService.forAnime(widget.anime);
      var w = await Store.watched(widget.profileId, widget.anime.id);
      // Best-effort migration: older installs keyed watched state by
      // AniList id. If the new Kitsu key is empty, copy the old entry
      // over once (never blocks, never overwrites existing state).
      if (w.isEmpty) {
        try {
          final al = await Kitsu.resolveAnilistId(widget.anime.id);
          if (al != null && al != widget.anime.id) {
            final old = await Store.watched(widget.profileId, al);
            if (old.isNotEmpty) {
              await Store.setWatched(widget.profileId, widget.anime.id, old);
              w = old;
            }
          }
        } catch (_) {}
      }
      final saved = await Store.savedEps(widget.profileId, widget.anime.id);
      String? libStatus;
      try {
        final lib = await Store.localLibrary(widget.profileId);
        final e = lib
            .where((e) =>
                e.key == 'local_${widget.anime.id}' ||
                e.anilistId == widget.anime.id)
            .firstOrNull;
        libStatus = e?.status;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _episodes = eps;
          _watched = w;
          _saved = saved;
          _libStatus = libStatus;
          _loading = false;
          // Website default: jump to the first range when the list is long.
          if (_rangeFrom == null && _total > 48) _rangeFrom = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleWatched(int ep) async {
    final next = Set<int>.from(_watched);
    if (next.contains(ep)) {
      next.remove(ep); // hole-preserving unmark, never clears neighbours
    } else {
      next.add(ep);
    }
    await Store.setWatched(widget.profileId, widget.anime.id, next);
    if (mounted) setState(() => _watched = next);
  }

  Future<void> _toggleSaved(int ep) async {
    final next = Set<int>.from(_saved);
    if (next.contains(ep)) {
      next.remove(ep);
    } else {
      next.add(ep);
    }
    await Store.setSavedEps(widget.profileId, widget.anime.id, next);
    if (mounted) setState(() => _saved = next);
  }

  /// Website's mark-all toggle: all watched -> unwatch all (local only,
  /// tracker progress left alone); otherwise mark all + one tracker push.
  Future<void> _markAllWatched() async {
    final total = _total;
    if (total <= 0) return;
    if (_allWatched) {
      await Store.setWatched(widget.profileId, widget.anime.id, <int>{});
      if (mounted) setState(() => _watched = <int>{});
      return;
    }
    final all = List.generate(total, (i) => i + 1).toSet();
    await Store.setWatched(widget.profileId, widget.anime.id, all);
    if (mounted) setState(() => _watched = all);
    await widget.onMarkWatched?.call(widget.anime, total);
  }

  Future<void> _setLayout(String v) async {
    setState(() {
      _layout = v;
      _filterOpen = false;
    });
    await Store.saveSettings(widget.settings.copyWith(episodeLayout: v));
  }

  Future<void> _setLibraryStatus(String? code) async {
    final a = widget.anime;
    final lib = await Store.localLibrary(widget.profileId);
    final i = lib.indexWhere(
        (e) => e.key == 'local_${a.id}' || e.anilistId == a.id);
    if (code == null) {
      if (i >= 0) {
        lib.removeAt(i);
        await Store.saveLocalLibrary(widget.profileId, lib);
      }
    } else {
      final old = i >= 0 ? lib[i] : null;
      final entry = LibraryEntry(
        key: 'local_${a.id}',
        source: 'local',
        title: a.title,
        cover: a.cover,
        status: code,
        progress: old?.progress ?? _watchedCount,
        total: _total > 0 ? _total : a.episodes,
        anilistId: a.id,
      );
      if (i >= 0) {
        lib[i] = entry;
      } else {
        lib.add(entry);
      }
      await Store.saveLocalLibrary(widget.profileId, lib);
    }
    if (mounted) setState(() => _libStatus = code);
  }

  Future<void> _openTrailer() async {
    final id = widget.anime.trailerId;
    if (id.isEmpty) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$id');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the trailer.')),
        );
      }
    }
  }

  Future<void> _playEpisode(int ep) async {
    // Resolve the addon stream id ONCE (Kitsu id -> AniList id). When the
    // title has no AniList mapping there is nothing to query addons with.
    final String streamId;
    try {
      streamId = await EpisodesService.streamIdFor(widget.anime, ep);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No streams found. Install an addon first (Settings > Addons) — the app ships with none.'),
        ),
      );
      return;
    }
    final addons =
        (await Store.addons(widget.profileId)).where((a) => a.enabled);
    final streams = <StreamSource>[];
    for (final a in addons) {
      try {
        streams.addAll(await AddonsService.streams(a, 'anime', streamId));
      } catch (_) {}
    }
    if (!mounted) return;
    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No streams found. Install an addon first (Settings > Addons) — the app ships with none.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          anime: widget.anime,
          episode: ep,
          streams: streams,
          settings: widget.settings,
          onMarkWatched: () async {
            final next = Set<int>.from(_watched)..add(ep);
            await Store.setWatched(widget.profileId, widget.anime.id, next);
            if (mounted) setState(() => _watched = next);
            await widget.onMarkWatched?.call(widget.anime, ep);
          },
        ),
      ),
    );
  }

  // ---------- episode ranges (website chunking) ----------
  List<_EpRange> _ranges(int total) {
    final chunk = total > 300
        ? 100
        : total > 96
            ? 24
            : 12;
    final out = <_EpRange>[];
    for (var s = 1; s <= total; s += chunk) {
      out.add(_EpRange(s, s + chunk - 1 > total ? total : s + chunk - 1));
    }
    return out;
  }

  List<int> get _visibleNumbers {
    final total = _total;
    if (total <= 0) return [];
    final from = _rangeFrom ?? 1;
    final to = _rangeFrom == null ? total : _ranges(total).firstWhere(
        (r) => r.from == _rangeFrom,
        orElse: () => _EpRange(1, total)).to;
    return [for (var n = from; n <= to; n++) n];
  }

  EpisodeInfo _epFor(int n) => _episodes
      .where((e) => e.number == n)
      .firstOrNull ??
      EpisodeInfo(number: n, title: _isMovie ? 'Complete Movie' : '');

  static String formatEpDate(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    if (m == null) return iso.length >= 10 ? iso.substring(0, 10) : '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mo = int.tryParse(m.group(2)!) ?? 1;
    return '${int.tryParse(m.group(3)!)} ${months[(mo - 1).clamp(0, 11)]} ${m.group(1)}';
  }

  // ---------- tracking sheet ----------
  Future<void> _showTrackingSheet() async {
    final t = await Store.tracker();
    if (!mounted) return;
    final alToken = (t['anilistToken'] as String?) ?? '';
    final alName = (t['anilistUsername'] as String?) ?? '';
    final skClient = (t['simklClientId'] as String?) ?? '';
    final skToken = (t['simklToken'] as String?) ?? '';
    final skName = (t['simklUsername'] as String?) ?? '';
    final skId =
        (t['simklIdFor_${widget.anime.id}'] as num?)?.toInt();
    final malUser = (t['malUsername'] as String?) ?? '';
    final total = _total;
    final count = _watchedCount;
    final maxEp =
        _watched.isEmpty ? 0 : _watched.reduce((x, y) => x > y ? x : y);

    Future<void> pushAniList() async {
      Navigator.of(context).pop();
      if (maxEp <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing watched yet to push.')),
        );
        return;
      }
      try {
        final al = await Kitsu.resolveAnilistId(widget.anime.id);
        if (al == null) throw Exception('no mapping');
        await Trackers.anilistSave(alToken, al, maxEp);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pushed $maxEp / $total to AniList.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AniList push failed.')),
          );
        }
      }
    }

    Future<void> pushSimkl() async {
      Navigator.of(context).pop();
      if (skId == null) return;
      try {
        await Trackers.simklSave(skClient, skToken, skId, maxEp);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pushed $maxEp / $total to Simkl.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Simkl push failed.')),
          );
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tracking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(widget.anime.title,
                  style: TextStyle(color: Colors.grey.shade400)),
              const SizedBox(height: 12),
              Text('This device: $count / $total episodes watched'),
              const SizedBox(height: 12),
              _trackerRow(
                'AniList',
                alToken.isNotEmpty
                    ? (alName.isNotEmpty ? '@$alName' : 'Connected')
                    : 'Not connected',
                alToken.isNotEmpty && maxEp > 0
                    ? TextButton(
                        onPressed: pushAniList,
                        child: Text('Push $maxEp / $total'))
                    : null,
              ),
              _trackerRow(
                'Simkl',
                skClient.isNotEmpty && skToken.isNotEmpty
                    ? (skName.isNotEmpty ? '@$skName' : 'Connected')
                    : 'Not connected',
                skClient.isNotEmpty && skToken.isNotEmpty && skId != null
                    ? TextButton(
                        onPressed: pushSimkl,
                        child: Text('Push $maxEp / $total'))
                    : null,
                note: skClient.isNotEmpty &&
                        skToken.isNotEmpty &&
                        skId == null
                    ? 'Not linked to this title'
                    : null,
              ),
              _trackerRow(
                'MyAnimeList',
                malUser.isNotEmpty ? '@$malUser' : 'Not connected',
                null,
                note: 'Read-only in this app',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackerRow(String name, String state, Widget? action,
      {String? note}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(note ?? state,
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13)),
              ],
            ),
          ),
          // ignore: use_null_aware_elements
          if (action != null) action,
        ],
      ),
    );
  }

  // ---------- widgets ----------
  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _genreChip(String g) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade700),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(g, style: const TextStyle(fontSize: 12)),
      );

  Widget _overlayBtn(
      {required IconData icon,
      required bool active,
      required VoidCallback onTap,
      required String tooltip}) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon,
                size: 18, color: active ? accent : Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _detailedCard(EpisodeInfo ep) {
    final watched = _watched.contains(ep.number);
    final saved = _saved.contains(ep.number);
    final title =
        ep.title.isNotEmpty ? ep.title : 'Episode ${ep.number}';
    return Card(
      color: const Color(0xFF1C1C1C),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _playEpisode(ep.number),
        child: Stack(
          children: [
            if (ep.still.isNotEmpty)
              Image.network(ep.still,
                  height: 170, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _stillFallback())
            else
              _stillFallback(),
            // Bottom shade for text legibility.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: _overlayBtn(
                icon: saved ? Icons.bookmark : Icons.bookmark_border,
                active: saved,
                onTap: () => _toggleSaved(ep.number),
                tooltip:
                    saved ? 'Saved — tap to unsave' : 'Save this episode',
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _overlayBtn(
                icon: watched
                    ? Icons.visibility
                    : Icons.visibility_outlined,
                active: watched,
                onTap: () => _toggleWatched(ep.number),
                tooltip:
                    watched ? 'Watched — tap to unmark' : 'Mark as watched',
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('S1E${ep.number}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  if (ep.overview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(ep.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade300)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        if (ep.runtime != null)
                          Text('${ep.runtime}m',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade300,
                                  fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (ep.airdate.isNotEmpty)
                          Text(formatEpDate(ep.airdate),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade300)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stillFallback() => Container(
        height: 170,
        width: double.infinity,
        color: const Color(0xFF2A2A2A),
        child: const Icon(Icons.play_circle_outline,
            size: 48, color: Colors.white54),
      );

  Widget _minimumRow(EpisodeInfo ep) {
    final watched = _watched.contains(ep.number);
    final title =
        ep.title.isNotEmpty ? ep.title : 'Episode ${ep.number}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ep.still.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(ep.still, width: 72, height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.play_circle_outline)),
            )
          : const Icon(Icons.play_circle_outline),
      title: Text('EP ${ep.number} · $title'),
      subtitle: ep.overview.isNotEmpty
          ? Text(ep.overview,
              maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: IconButton(
        icon: Icon(
          watched ? Icons.visibility : Icons.visibility_outlined,
          color: watched ? Theme.of(context).colorScheme.primary : null,
        ),
        onPressed: () => _toggleWatched(ep.number),
        tooltip: 'Mark watched / unwatch',
      ),
      onTap: () => _playEpisode(ep.number),
    );
  }

  Widget _countPill(
      {required String label,
      required int count,
      required bool active,
      required VoidCallback onTap}) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent : _card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.black : Colors.white)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: active
                    ? Colors.black26
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      color: active ? Colors.black : Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    final accent = Theme.of(context).colorScheme.primary;
    final total = _total;
    final nextEp = _nextEp;
    final count = _watchedCount;
    final ranges = _ranges(total);
    final numbers = _visibleNumbers;
    final desc = a.description;
    final showMaxBtn = desc.length > 200;

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Clean banner (website mobile): full image, nothing else.
                if (a.banner.isNotEmpty)
                  Image.network(a.banner,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(height: 120, color: _card))
                else
                  Container(height: 120, color: _card),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (a.score != null)
                            _chip(
                                '★ ${(a.score! / 10).toStringAsFixed(1)}'),
                          if (a.format.isNotEmpty) _chip(a.format),
                          if (a.status.isNotEmpty)
                            _chip(a.status.replaceAll('_', ' ')),
                          if (a.year != null) _chip('${a.year}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(a.title,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      if (a.romaji.isNotEmpty && a.romaji != a.title)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(a.romaji,
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14)),
                        ),
                      if (a.genres.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                a.genres.map(_genreChip).toList(),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      const Text('About this anime',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (desc.isNotEmpty) ...[
                        Text(desc,
                            maxLines:
                                _synopsisExpanded ? null : 4,
                            overflow: _synopsisExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.45)),
                        if (showMaxBtn)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              onPressed: () => setState(() =>
                                  _synopsisExpanded =
                                      !_synopsisExpanded),
                              child: Text(
                                  _synopsisExpanded
                                      ? 'Minimize'
                                      : 'Maximize',
                                  style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                      if (total > 0 && !_isMovie)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 4, bottom: 10),
                          child: Text(
                              '◦ Episode $nextEp · ${count > 0 ? 'Continue watching' : 'Start watching'}',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 13)),
                        ),
                      if (total > 0) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(26)),
                              textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _playEpisode(nextEp),
                            child: Text(_isMovie
                                ? '▶ Play Movie'
                                : '▶ Play Ep $nextEp'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // Library / My List (website's bookmark pill).
                          Expanded(
                            child: _actionPill(
                              child: PopupMenuButton<String>(
                                color: _card,
                                tooltip: _libStatus == null
                                    ? 'Add to Library'
                                    : _libStatusName(_libStatus!),
                                onSelected: _setLibraryStatus,
                                itemBuilder: (_) => [
                                  for (final e in _libMenu)
                                    PopupMenuItem(
                                      value: e.$2,
                                      child: Row(
                                        children: [
                                          Text(e.$1),
                                          const Spacer(),
                                          if (_libStatus == e.$2)
                                            Icon(Icons.check,
                                                size: 18,
                                                color: accent),
                                        ],
                                      ),
                                    ),
                                  if (_libStatus != null)
                                    const PopupMenuDivider(),
                                  if (_libStatus != null)
                                    const PopupMenuItem(
                                      value: null,
                                      child: Text('Remove from Library',
                                          style: TextStyle(
                                              color: Colors.redAccent)),
                                    ),
                                ],
                                child: Icon(
                                  _libStatus == null
                                      ? Icons.bookmark_border
                                      : Icons.bookmark,
                                  color: _libStatus == null
                                      ? Colors.white
                                      : accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Mark all watched (website's ✓ pill).
                          Expanded(
                            child: _actionPill(
                              child: IconButton(
                                tooltip: _allWatched
                                    ? 'All watched — tap to unwatch'
                                    : 'Mark all watched',
                                onPressed:
                                    total > 0 ? _markAllWatched : null,
                                icon: Icon(Icons.check,
                                    color: _allWatched
                                        ? accent
                                        : Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Trailer (website's 🎬 pill) — only when known.
                          if (a.trailerId.isNotEmpty)
                            Expanded(
                              child: _actionPill(
                                child: IconButton(
                                  tooltip: 'Watch trailer',
                                  onPressed: _openTrailer,
                                  icon: const Text('🎬',
                                      style: TextStyle(fontSize: 22)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (total > 0) ...[
                        // Watching Progress card (website).
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text('Watching Progress',
                                      style: TextStyle(
                                          color:
                                              Colors.grey.shade400,
                                          fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Text('$count / $total',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                          color:
                                              Colors.grey.shade700),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  12)),
                                    ),
                                    onPressed: _showTrackingSheet,
                                    icon: const Icon(Icons.settings,
                                        size: 16),
                                    label: const Text('Tracking'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: total > 0
                                      ? count / total
                                      : 0,
                                  minHeight: 6,
                                  backgroundColor:
                                      const Color(0xFF3A3A3A),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                          accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('EPISODES',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Colors.grey)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            InkWell(
                              onTap: () => setState(() =>
                                  _filterOpen = !_filterOpen),
                              borderRadius:
                                  BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _card,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: _filterOpen
                                      ? Border.all(color: accent)
                                      : null,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.tune, size: 16),
                                    SizedBox(width: 6),
                                    Text('Filter',
                                        style: TextStyle(
                                            fontWeight:
                                                FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _countPill(
                              label: 'All',
                              count: total,
                              active: _rangeFrom == null,
                              onTap: () =>
                                  setState(() => _rangeFrom = null),
                            ),
                            const SizedBox(width: 8),
                            Container(
                                width: 1,
                                height: 28,
                                color: Colors.grey.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final r in ranges) ...[
                                      _countPill(
                                        label: r.label,
                                        count: r.count,
                                        active:
                                            _rangeFrom == r.from,
                                        onTap: () => setState(
                                            () => _rangeFrom = r.from),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_filterOpen)
                          Container(
                            margin:
                                const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius:
                                  BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text('EPISODE DESIGN',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                        color: Colors.grey)),
                                const SizedBox(height: 4),
                                _designRow('minimum', 'Minimum',
                                    'Compact rows'),
                                _designRow('detailed', 'Detailed',
                                    'Big cards with synopsis'),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          // Skeleton matches the selected episode layout,
                          // like the website's transparent episode skeletons.
                          child: _layout == 'detailed'
                              ? skeletonEpisodeDetailed(count: 3)
                              : skeletonEpisodeMinimum(count: 5),
                        ),
                      if (_error != null)
                        Text('Episodes could not load: $_error'),
                      if (!_loading && _error == null)
                        if (_layout == 'detailed')
                          ...numbers.map((n) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 10),
                                child: _detailedCard(_epFor(n)),
                              ))
                        else
                          ...numbers.map(
                              (n) => _minimumRow(_epFor(n))),
                      if (!_loading &&
                          _error == null &&
                          numbers.isEmpty)
                        const Text(
                            'No episode list available for this title yet.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Floating back button over the banner (website mobile).
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({required Widget child}) => Container(
        height: 56,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: child),
      );

  Widget _designRow(String value, String name, String hint) {
    final active = _layout == value;
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => _setLayout(value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  Text(hint,
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12)),
                ],
              ),
            ),
            if (active)
              Icon(Icons.check, color: accent)
            else
              Icon(Icons.circle_outlined,
                  color: Colors.grey.shade600, size: 20),
          ],
        ),
      ),
    );
  }
}
