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
import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/episodes.dart';
import '../services/kitsu.dart';
import '../services/anilist.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../widgets/ga_image.dart';
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
  ('Rewatching', 'REPEATING'),
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
  String _studio = ''; // main studio from AniList, '' = unknown (no chip)

  @override
  void initState() {
    super.initState();
    _layout = const {'minimum', 'compact'}
            .contains(widget.settings.episodeLayout)
        ? widget.settings.episodeLayout
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
      // Resolve the AniList id once: needed for the watched-state
      // migration below and for the main-studio chip (website parity).
      int? alId;
      try {
        alId = await Kitsu.resolveAnilistId(widget.anime.id);
      } catch (_) {}
      // Best-effort migration: older installs keyed watched state by
      // AniList id. If the new Kitsu key is empty, copy the old entry
      // over once (never blocks, never overwrites existing state).
      if (w.isEmpty && alId != null && alId != widget.anime.id) {
        try {
          final old = await Store.watched(widget.profileId, alId);
          if (old.isNotEmpty) {
            await Store.setWatched(widget.profileId, widget.anime.id, old);
            w = old;
          }
        } catch (_) {}
      }
      // Main studio chip (website parity: details badge row shows the
      // main studio, e.g. "Toei Animation"). Best-effort; no chip when
      // unknown.
      String studio = '';
      if (alId != null) {
        try {
          studio = (await AniList.details(alId)).studio;
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
          _studio = studio;
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
    // Addon stream resolution (website parity):
    // 1) installed + enabled addons only (re-read fresh: a disable/remove
    //    in Settings > Addons takes effect on the next play);
    // 2) per-addon /stream/<type>/ path (general addons want "series",
    //    anime-only ones "anime" — hardcoding "anime" 404s on general
    //    addons, the reported "no stream addon found" bug);
    // 3) every id dialect the addon understands (kitsu:/tt:/anilist:/
    //    mal:), merged and de-duplicated.
    // 4) Fallback: if the current profile has no addons, check other
    //    profiles (addons are per-profile in storage, but the user
    //    expects an installed addon to work everywhere).
    var addons = (await Store.addons(widget.profileId))
        .where((a) => a.enabled)
        .toList();
    if (addons.isEmpty) {
      // Fallback: try addons from any profile.
      final all = await Store.allAddons();
      addons = all.where((a) => a.enabled).toList();
    }
    if (addons.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No stream addon installed or enabled. Add one under Settings > Addons — the app ships with none.'),
        ),
      );
      return;
    }
    // Legacy records saved before types/idPrefixes existed: refetch the
    // manifest once so the per-addon type + id dialect resolve correctly.
    for (var i = 0; i < addons.length; i++) {
      final a = addons[i];
      if (a.types.isEmpty) {
        try {
          final fresh = await AddonsService.fetchManifest(a.manifestUrl);
          final updated = a.copyWith(
            types: fresh.types,
            idPrefixes: fresh.idPrefixes,
          );
          addons[i] = updated;
          final all = await Store.addons(widget.profileId);
          final idx =
              all.indexWhere((e) => e.manifestUrl == a.manifestUrl);
          if (idx >= 0) {
            all[idx] = updated;
            await Store.saveAddons(widget.profileId, all);
          }
        } catch (_) {}
      }
    }
    final isMovie = widget.anime.format.toUpperCase() == 'MOVIE';
    final ids = await AddonIdResolver.resolve(widget.anime);
    final streams = <StreamSource>[];
    final seen = <String>{};
    final noIdNotes = <String>[];
    for (final a in addons) {
      final type = AddonsService.streamTypeFor(a, isMovie);
      final sids = AddonIdResolver.streamIdsFor(
        a,
        ids,
        title: widget.anime.title,
        isMovie: isMovie,
        episode: ep,
      );
      if (sids.isEmpty) {
        noIdNotes.add(
            '${a.name} understands: ${a.idPrefixes.join(', ')}');
        continue;
      }
      for (final sid in sids) {
        try {
          final found = await AddonsService.streams(a, type, sid);
          for (final s in found) {
            if (s.url.isNotEmpty && seen.add(s.url)) streams.add(s);
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    if (streams.isEmpty) {
      final msg = noIdNotes.length == addons.length
          ? 'No compatible ID for this title — ${noIdNotes.join('; ')}.'
          : 'No streams found for episode $ep. The installed addon(s) returned nothing for this title.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
      backgroundColor: GaColors.of(context).card,
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

  // Website `.ep-save` / `.ep-eye`: 28px circles, dark translucent bg,
  // 1.5px white-35% border; save turns gold, eye turns green when on.
  Widget _overlayBtn({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required Color activeBorder,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Opaque enough to stay visible on bright thumbnails.
            color: active
                ? activeColor
                : const Color.fromRGBO(10, 12, 18, 0.85),
            border: Border.all(
              color: active
                  ? activeBorder
                  : Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Icon(icon,
              size: 15,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55)),
        ),
      ),
    );
  }

  // Website `.ep-big` (Detailed): 84vw card in a horizontal strip, 172px
  // still, shade gradient, save/eye top corners, body overlaid at the
  // bottom: S1E chip, title, 2-line synopsis, runtime/date footer.
  Widget _detailedCard(EpisodeInfo ep, double width) {
    final watched = _watched.contains(ep.number);
    final saved = _saved.contains(ep.number);
    final title =
        ep.title.isNotEmpty ? ep.title : 'Episode ${ep.number}';
    // Website falls back to the title's episode duration here; the app
    // doesn't carry that field, so runtime comes from the episode only.
    final runtime = ep.runtime != null ? '${ep.runtime}m' : '';
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => _playEpisode(ep.number),
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox(
              height: 200,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ep.still.isNotEmpty
                        ? GaImage(
                            url: ep.still,
                            fit: BoxFit.cover,
                            errorFallback: _stillFallback(height: 200),
                          )
                        : _stillFallback(height: 200),
                  ),
                  // Website `.ep-big-shade`: transparent 26% -> black 85%.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.26, 0.88],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _overlayBtn(
                      icon: saved
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      active: saved,
                      activeColor: const Color(0xFFB98A1C),
                      activeBorder: const Color(0xFFE8B93C),
                      onTap: () => _toggleSaved(ep.number),
                      tooltip: saved
                          ? 'Saved — tap to unsave'
                          : 'Save this episode',
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _overlayBtn(
                      icon: watched
                          ? Icons.visibility
                          : Icons.visibility_outlined,
                      active: watched,
                      activeColor: Theme.of(context).colorScheme.primary,
                      activeBorder: Theme.of(context).colorScheme.primary,
                      onTap: () => _toggleWatched(ep.number),
                      tooltip: watched
                          ? 'Watched — tap to unmark'
                          : 'Mark as watched',
                    ),
                  ),
                  // Website `.ep-big-body`: absolute bottom, 12/14 padding.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('S1E${ep.number}',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 6),
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3)),
                          if (ep.overview.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(ep.overview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: Color(0xFFD8D8D8))),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                if (runtime.isNotEmpty)
                                  Text(runtime,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFCFCFCF),
                                          fontWeight: FontWeight.w600)),
                                const Spacer(),
                                if (ep.airdate.isNotEmpty)
                                  Text(formatEpDate(ep.airdate),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFCFCFCF),
                                          fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stillFallback({double height = 170}) => Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFF2A2A2A),
        child: const Icon(Icons.play_circle_outline,
            size: 48, color: Colors.white54),
      );

  // Website `.ep-pic` (Minimal): full-width 16:9 picture card, save/eye
  // top corners, white-bordered "EP n" badge bottom-left, date badge
  // bottom-right. No title text — picture only + EP/date inside.
  Widget _minimumCard(EpisodeInfo ep) {
    final watched = _watched.contains(ep.number);
    final saved = _saved.contains(ep.number);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _playEpisode(ep.number),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ep.still.isNotEmpty
                        ? GaImage(
                            url: ep.still,
                            fit: BoxFit.cover,
                            errorFallback: _stillFallback(height: 120),
                          )
                        : _stillFallback(height: 120),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _overlayBtn(
                      icon: saved
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      active: saved,
                      activeColor: const Color(0xFFB98A1C),
                      activeBorder: const Color(0xFFE8B93C),
                      onTap: () => _toggleSaved(ep.number),
                      tooltip: saved
                          ? 'Saved — tap to unsave'
                          : 'Save this episode',
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _overlayBtn(
                      icon: watched
                          ? Icons.visibility
                          : Icons.visibility_outlined,
                      active: watched,
                      activeColor: Theme.of(context).colorScheme.primary,
                      activeBorder: Theme.of(context).colorScheme.primary,
                      onTap: () => _toggleWatched(ep.number),
                      tooltip: watched
                          ? 'Watched — tap to unmark'
                          : 'Mark as watched',
                    ),
                  ),
                  // Website `.ep-badge`: white-bordered EP pill.
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color:
                            const Color.fromRGBO(16, 18, 24, 0.87),
                        border: Border.all(
                            color: Colors.white, width: 1.6),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('EP ${ep.number}',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: Colors.white)),
                    ),
                  ),
                  if (ep.airdate.isNotEmpty)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color.fromRGBO(16, 18, 24, 0.72),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(formatEpDate(ep.airdate),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE8E8E8))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Compact episode layout: dense ~60px rows for long episode lists.
  Widget _compactRow(EpisodeInfo ep) {
    final watched = _watched.contains(ep.number);
    final saved = _saved.contains(ep.number);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _playEpisode(ep.number),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: GaColors.of(context).card,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: watched
                      ? accent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: watched
                    ? Icon(Icons.check, size: 18, color: accent)
                    : Text('${ep.number}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        ep.title.isNotEmpty
                            ? ep.title
                            : 'Episode ${ep.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    if (ep.airdate.isNotEmpty)
                      Text(formatEpDate(ep.airdate),
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11)),
                  ],
                ),
              ),
              if (saved)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.bookmark,
                      size: 16, color: Color(0xFFE8B93C)),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                tooltip: watched ? 'Watched — tap to unmark' : 'Mark as watched',
                icon: Icon(
                    watched ? Icons.visibility : Icons.visibility_outlined,
                    size: 18,
                    color: watched ? accent : Colors.grey.shade400),
                onPressed: () => _toggleWatched(ep.number),
              ),
            ],
          ),
        ),
      ),
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
          color: active ? accent : GaColors.of(context).card,
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
                  GaImage(
                    url: a.banner,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorFallback: Container(
                        height: 120, color: GaColors.of(context).card),
                  )
                else
                  Container(height: 120, color: GaColors.of(context).card),
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
                          // Main studio, last (website parity: hchip).
                          if (_studio.isNotEmpty) _chip(_studio),
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
                                      ? 'Show less'
                                      : 'Show more',
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
                            // Website: white pill, BLACK play triangle, black
                            // text. A real icon, never an emoji/text glyph.
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow,
                                    color: Colors.black, size: 22),
                                const SizedBox(width: 4),
                                Text(_isMovie
                                    ? 'Play Movie'
                                    : 'Play Ep $nextEp'),
                              ],
                            ),
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
                                color: GaColors.of(context).card,
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
                            color: GaColors.of(context).card,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text('Watching Progress',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color:
                                                Colors.grey.shade400,
                                            fontSize: 14)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('$count / $total',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 12),
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
                                  color: GaColors.of(context).card,
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
                              color: GaColors.of(context).card,
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
                                _designRow('compact', 'Compact',
                                    'Dense rows'),
                                _designRow('detailed', 'Detailed',
                                    'Big cards with synopsis'),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                      if (_loading)
                        // Skeleton matches the selected episode layout,
                        // in the same inset context as the real list
                        // (the parent already pads 16) — no extra padding,
                        // or the ghost cards size/position would shift.
                        _layout == 'detailed'
                            ? skeletonEpisodeDetailed(count: 3)
                            : skeletonEpisodeMinimum(count: 5),
                      if (_error != null)
                        Text('Episodes could not load: $_error'),
                      if (!_loading && _error == null)
                        if (_layout == 'detailed')
                          // Website `.ep-big-strip`: horizontal strip of
                          // 84vw cards (website mobile: 84vw).
                          SizedBox(
                            height: 200,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: numbers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (_, i) => _detailedCard(
                                  _epFor(numbers[i]),
                                  MediaQuery.of(context).size.width *
                                      0.84),
                            ),
                          )
                        else if (_layout == 'compact')
                          ...numbers
                              .map((n) => _compactRow(_epFor(n)))
                        else
                          ...numbers
                              .map((n) => _minimumCard(_epFor(n))),
                      if (!_loading &&
                          _error == null &&
                          numbers.isEmpty)
                        const Text(
                            'Episode details will appear here once AniList data loads.'),
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
          color: GaColors.of(context).card,
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
