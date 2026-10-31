// Details + Episodes — website mobile-parity layout.
// Banner with back button, chips, collapsible synopsis, Play Ep N pill,
// library / mark-all-watched / trailer action row, Watching Progress card
// with tracking sheet, episode filter row (Filter menu + All + ranges),
// and Detailed / Minimum episode layouts (persisted in AppSettings).
// Episodes are numbered from the AniList total; watched + saved state is local per profile.
// Tapping an episode opens the stream picker, then the player.
// If no addon is installed, streams are empty and the player screen
// explains that — the app never invents a stream source.
import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/episodes.dart';
import '../services/anilist.dart';
import '../widgets/ga_image.dart';
import '../services/trackers.dart';
import '../services/tracker_oauth.dart';
import 'streams.dart';
import '../store.dart';
import '../widgets/skeletons.dart';
import '../widgets/glass_surface.dart';

class DetailsScreen extends StatefulWidget {
  final Anime anime;
  final String profileId;
  final AppSettings settings;
  final int initialProgress;
  final Future<void> Function(Anime anime, int episode)? onMarkWatched;
  const DetailsScreen({
    super.key,
    required this.anime,
    required this.profileId,
    required this.settings,
    this.initialProgress = 0,
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

/// Per-tracker edit state for the Tracker Tool dialog.
class _TrackerEdit {
  String status; // app codes: CURRENT / COMPLETED / PLANNING / PAUSED / DROPPED
  int progress;
  double score = 0; // 0-10, 0 = unset
  DateTime? startDate;
  DateTime? endDate;
  bool advancedOpen = false;
  String memo = ''; // Simkl only
  bool isPrivate = false; // Simkl only (UI state; Simkl API contract unverified)

  _TrackerEdit({this.status = 'CURRENT', this.progress = 0});
}

const _trackerStatusLabels = [
  'Watching',
  'Completed',
  'Plan to Watch',
  'On Hold',
  'Dropped',
];
const _trackerStatusCodes = [
  'CURRENT',
  'COMPLETED',
  'PLANNING',
  'PAUSED',
  'DROPPED',
];

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
  // Canonical anime for this screen. Calendar/tracker entries arrive
  // as AniList objects (anilistId set, id = AniList id); _load() swaps
  // in the AniList object for the same show so episodes, images and all
  // local state agree with the same title opened from Home.
  late Anime _anime;

  @override
  void initState() {
    super.initState();
    _layout = const {'minimum', 'compact'}
            .contains(widget.settings.episodeLayout)
        ? widget.settings.episodeLayout
        : 'detailed';
    _anime = widget.anime;
    _load();
  }

  bool get _isMovie => _anime.format == 'MOVIE';

  int get _total {
    if (_isMovie) return 1;
    if (_episodes.isNotEmpty) return _episodes.length;
    return _anime.episodes ?? 0;
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
      // Catalogue is AniList-based: _anime.id IS the AniList id.
      // If an entry arrived with a differing anilistId (legacy state),
      // OR with missing banner/description (stripped calendar/MAL entry),
      // refresh from AniList so posters/banner and local state agree.
      if ((_anime.anilistId != null && _anime.anilistId != _anime.id) ||
          _anime.banner.isEmpty ||
          _anime.description.isEmpty) {
        final targetId = _anime.anilistId ?? _anime.id;
        if (targetId > 0) {
          try {
            final fresh = await AniList.details(targetId);
            // Keep the airing info the calendar already knew.
            _anime = fresh.copyWith(
              anilistId: targetId,
              nextEpisode: _anime.nextEpisode ?? fresh.nextEpisode,
              airingAt: _anime.airingAt ?? fresh.airingAt,
            );
          } catch (_) {}
        }
      }
      final a = _anime;
      final alId = a.anilistId;

      // Parallel where possible: episodes + watched + saved + library fly
      // together; the studio call fires only when the catalog didn't carry
      // it. Previously these were 5+ sequential awaits with the AniList-id
      // lookup done twice — that was the visible lag on calendar opens.
      final results = await Future.wait<dynamic>([
        EpisodesService.forAnime(a),
        Store.watched(widget.profileId, a.id),
        Store.savedEps(widget.profileId, a.id),
        Store.localLibrary(widget.profileId),
        if (a.studio.isEmpty && alId != null)
          AniList.details(alId)
              .then<String>((d) => d.studio, onError: (_) => '')
        else
          Future<String>.value(a.studio),
      ]);
      final eps = results[0] as List<EpisodeInfo>;
      var w = results[1] as Set<int>;
      final saved = results[2] as Set<int>;
      final lib = results[3] as List<LibraryEntry>;
      final studio = results[4] as String;
      // Sync tracker progress: if local watched is empty, populate from
      // the tracker's progress (e.g. opened from MAL/Simkl/AniList tab).
      // Falls back to widget.initialProgress passed from the library card.
      if (w.isEmpty) {
        final existing = lib
            .where((e) => e.key == 'local_${a.id}' || e.anilistId == a.id)
            .firstOrNull;
        final prog = (existing?.progress ?? 0) > 0
            ? existing!.progress
            : widget.initialProgress;
        if (prog > 0) {
          w = List.generate(prog, (i) => i + 1).toSet();
          await Store.setWatched(widget.profileId, a.id, w);
        }
      }

      // Best-effort migration: watched state written under a differing
      // id key (legacy installs) is copied to the current id once,
      // never overwriting existing state.
      if (w.isEmpty && alId != null && alId != a.id) {
        try {
          final old = await Store.watched(widget.profileId, alId);
          if (old.isNotEmpty) {
            await Store.setWatched(widget.profileId, a.id, old);
            w = old;
          }
        } catch (_) {}
      }

      String? libStatus;
      try {
        final e = lib
            .where((e) => e.key == 'local_${a.id}' || e.anilistId == a.id)
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
    await Store.setWatched(widget.profileId, _anime.id, next);
    if (mounted) setState(() => _watched = next);
  }

  Future<void> _toggleSaved(int ep) async {
    final next = Set<int>.from(_saved);
    if (next.contains(ep)) {
      next.remove(ep);
    } else {
      next.add(ep);
    }
    await Store.setSavedEps(widget.profileId, _anime.id, next);
    if (mounted) setState(() => _saved = next);
  }

  /// Website's mark-all toggle: all watched -> unwatch all (local only,
  /// tracker progress left alone); otherwise mark all + one tracker push.
  Future<void> _markAllWatched() async {
    final total = _total;
    if (total <= 0) return;
    if (_allWatched) {
      await Store.setWatched(widget.profileId, _anime.id, <int>{});
      if (mounted) setState(() => _watched = <int>{});
      return;
    }
    final all = List.generate(total, (i) => i + 1).toSet();
    await Store.setWatched(widget.profileId, _anime.id, all);
    if (mounted) setState(() => _watched = all);
    await widget.onMarkWatched?.call(_anime, total);
  }

  Future<void> _setLayout(String v) async {
    setState(() {
      _layout = v;
      _filterOpen = false;
    });
    await Store.saveSettings(widget.settings.copyWith(episodeLayout: v));
  }

  Future<void> _setLibraryStatus(String? code) async {
    final a = _anime;
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
    final id = _anime.trailerId;
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
    // Stream fetch lives in the Streams screen: per-addon groups,
    // progressive loading, user picks a link.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamsScreen(
          anime: _anime,
          episode: ep,
          profileId: widget.profileId,
          settings: widget.settings,
          episodes: _episodes,
          watchedEpisodes: _watched,
          onMarkWatched: () async {
            final next = Set<int>.from(_watched)..add(ep);
            await Store.setWatched(widget.profileId, _anime.id, next);
            if (mounted) setState(() => _watched = next);
            await widget.onMarkWatched?.call(_anime, ep);
          },
        ),
      ),
    );
    // Watched may have changed in the player (85% rule).
    try {
      final w = await Store.watched(widget.profileId, _anime.id);
      if (mounted) setState(() => _watched = w);
    } catch (_) {}
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
    if (iso.isEmpty) return '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    if (m == null) {
      final y = RegExp(r'(\d{4})').firstMatch(iso);
      return y != null ? y.group(1)! : '';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mo = int.tryParse(m.group(2)!) ?? 1;
    return '${int.tryParse(m.group(3)!)} ${months[(mo - 1).clamp(0, 11)]} ${m.group(1)}';
  }

  // ---------- tracker tool dialog (redesign: per-tracker glass bubbles) ----------
  Future<void> _showTrackingDialog() async {
    Map<String, dynamic> t = await Store.tracker();
    if (!mounted) return;

    final alMediaId = _anime.anilistId ?? _anime.id;
    String alToken = '', alName = '', skClient = '', skToken = '', skName = '';
    String malToken = '', malUser = '';
    int? skId, malId;
    bool alConnected = false, skConnected = false, malConnected = false;

    // Re-derived from [t] on every dialog rebuild, so a mid-dialog
    // OAuth connect refreshes the bubbles without closing the dialog.
    void derive() {
      alToken = (t['anilistToken'] as String?) ?? '';
      alName = (t['anilistUsername'] as String?) ?? '';
      skClient = (t['simklClientId'] as String?) ?? '';
      skToken = (t['simklToken'] as String?) ?? '';
      skName = (t['simklUsername'] as String?) ?? '';
      skId =
          (t['simklIdFor_${_anime.anilistId ?? _anime.id}'] as num?)?.toInt();
      malToken = (t['malToken'] as String?) ?? '';
      malUser = (t['malUsername'] as String?) ?? '';
      malId = _anime.malId;
      alConnected = alToken.isNotEmpty;
      skConnected = skToken.isNotEmpty && skClient.isNotEmpty;
      malConnected = malToken.isNotEmpty;
    }

    derive();

    final total = _total > 0 ? _total : (_anime.episodes ?? 0);
    final currentMax =
        _watched.isEmpty ? 0 : _watched.reduce((x, y) => x > y ? x : y);
    String initialStatus() =>
        (total > 0 && currentMax >= total) ? 'COMPLETED' : 'CURRENT';

    final alEdit = _TrackerEdit(status: initialStatus(), progress: currentMax);
    final skEdit = _TrackerEdit(status: initialStatus(), progress: currentMax);
    final malEdit = _TrackerEdit(status: initialStatus(), progress: currentMax);
    final memoCtrl = TextEditingController();

    const green = Color(0xFF22C55E);
    const red = Color(0xFFE5484D);
    const amber = Color(0xFFF5A524);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String fmtDate(DateTime? d) =>
        d == null ? '—' : '${d.day} ${months[d.month - 1]} ${d.year}';

    // Direct OAuth for the given tracker ('anilist' | 'mal' | 'simkl').
    // No settings-screen detour: on return the dialog refreshes in place.
    Future<void> connectTracker(StateSetter setD, String which) async {
      bool ok = false;
      switch (which) {
        case 'anilist':
          ok = await TrackerOAuth.connectAnilist();
          break;
        case 'mal':
          ok = await TrackerOAuth.connectMal();
          break;
        case 'simkl':
          ok = await TrackerOAuth.connectSimkl();
          break;
      }
      if (!ok) return;
      t = await Store.tracker();
      derive();
      setD(() {});
      _load();
    }

    Future<void> confirmDelete(BuildContext dCtx, String trackerName,
        Future<void> Function() action) async {
      final ok = await showDialog<bool>(
        context: dCtx,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Delete from $trackerName?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          content: Text(
              'This removes "${_anime.title}" from your $trackerName list.',
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70))),
            TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Color(0xFFE5484D),
                        fontWeight: FontWeight.w800))),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await action();
        if (!dCtx.mounted) return;
        ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
            content: Text('Deleted from $trackerName'),
            backgroundColor: const Color(0xFF1E1F24)));
        Navigator.of(dCtx).pop();
      } catch (e) {
        if (!dCtx.mounted) return;
        ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: const Color(0xFF1E1F24)));
      }
    }

    Future<void> saveAll(BuildContext dCtx) async {
      Navigator.of(dCtx).pop();
      final mId = malId; // local copy: null-promotion inside this closure
      var prog = 0;
      if (alConnected && alEdit.progress > prog) prog = alEdit.progress;
      if (skConnected && skEdit.progress > prog) prog = skEdit.progress;
      if (malConnected && malEdit.progress > prog) prog = malEdit.progress;

      final newWatched = List.generate(prog, (i) => i + 1).toSet();
      await Store.setWatched(widget.profileId, _anime.id, newWatched);
      if (mounted) setState(() => _watched = newWatched);

      final pushed = <String>[];
      if (alConnected && alMediaId > 0) {
        try {
          await Trackers.anilistSaveFull(alToken, alMediaId,
              progress: alEdit.progress,
              status: alEdit.status,
              score: alEdit.score > 0 ? alEdit.score : null,
              startDate: alEdit.startDate,
              endDate: alEdit.endDate);
          pushed.add('AniList');
        } catch (_) {}
      }
      if (skConnected && skId != null) {
        try {
          await Trackers.simklSaveFull(skClient, skToken,
              simklId: skId,
              anilistId: alMediaId > 0 ? alMediaId : null,
              title: _anime.title,
              progress: skEdit.progress,
              status: skEdit.status,
              memo: skEdit.memo);
          pushed.add('Simkl');
        } catch (_) {}
      }
      if (malConnected && mId != null && mId > 0) {
        try {
          await Trackers.malSave(malToken, mId,
              status: malEdit.status,
              episodes: malEdit.progress,
              score: malEdit.score > 0 ? malEdit.score : null);
          if (malEdit.startDate != null || malEdit.endDate != null) {
            await Trackers.malUpdateDates(malToken, mId,
                startDate: malEdit.startDate, finishDate: malEdit.endDate);
          }
          pushed.add('MAL');
        } catch (_) {}
      }
      await widget.onMarkWatched?.call(_anime, prog);
      if (mounted) {
        final extra =
            pushed.isNotEmpty ? ' & synced to ${pushed.join(', ')}' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Saved: Ep $prog / ${total > 0 ? total : '—'}$extra'),
            backgroundColor: const Color(0xFF1E1F24)));
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) {
          final maxAllowed = total > 0 ? total : 9999;
          // Local final copies so closures below get null-promotion.
          final sId = skId;
          final mId = malId;

          Widget thickSlider({
            required double value,
            required double max,
            required int divisions,
            required ValueChanged<double> onChanged,
          }) {
            final accent = Theme.of(dCtx).colorScheme.primary;
            return SliderTheme(
              data: SliderTheme.of(dCtx).copyWith(
                trackHeight: 18,
                activeTrackColor: accent,
                inactiveTrackColor:
                    Colors.white.withValues(alpha: 0.12),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 12),
                thumbColor: Colors.white,
                overlayColor: accent.withValues(alpha: 0.25),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 20),
              ),
              child: Slider(
                value: value.clamp(0.0, max),
                min: 0,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            );
          }

          Widget stepBtn(IconData icon, VoidCallback? onTap) {
            return InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Icon(icon,
                    size: 18,
                    color: onTap == null ? Colors.white24 : Colors.white),
              ),
            );
          }

          Widget statusPill(_TrackerEdit edit) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Theme.of(dCtx).colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                      color: Theme.of(dCtx)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35),
                      blurRadius: 12)
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: edit.status,
                  dropdownColor: const Color(0xFF22242B),
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: Theme.of(dCtx).colorScheme.onPrimary, size: 20),
                  style: TextStyle(
                      color: Theme.of(dCtx).colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                  items: [
                    for (var i = 0; i < _trackerStatusLabels.length; i++)
                      DropdownMenuItem(
                        value: _trackerStatusCodes[i],
                        child: Text(_trackerStatusLabels[i],
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setD(() => edit.status = v);
                  },
                ),
              ),
            );
          }

          Widget datePill(
              String label, DateTime? date, VoidCallback onTap) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Center(
                        child: Text(fmtDate(date),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
              ],
            );
          }

          Future<void> pickDate(_TrackerEdit edit, bool isStart) async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: dCtx,
              initialDate:
                  (isStart ? edit.startDate : edit.endDate) ?? now,
              firstDate: DateTime(1990),
              lastDate: DateTime(now.year + 2, 12, 31),
            );
            if (picked != null) {
              setD(() {
                if (isStart) {
                  edit.startDate = picked;
                } else {
                  edit.endDate = picked;
                }
              });
            }
          }

          Widget deleteBtn(
              String tracker, Future<void> Function() action) {
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => confirmDelete(dCtx, tracker, action),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete entry',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            );
          }

          Widget advancedSection({
            required _TrackerEdit edit,
            required bool showDates,
            required bool showMemo,
            required Widget deleteButton,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () =>
                      setD(() => edit.advancedOpen = !edit.advancedOpen),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Text('Advanced',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.2)),
                            color:
                                Colors.white.withValues(alpha: 0.06),
                          ),
                          child: Icon(
                              edit.advancedOpen
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                if (edit.advancedOpen) ...[
                  if (showDates) ...[
                    Row(
                      children: [
                        Expanded(
                            child: datePill('Start date',
                                edit.startDate, () => pickDate(edit, true))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: datePill('End date', edit.endDate,
                                () => pickDate(edit, false))),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showMemo) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Memo',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text('${edit.memo.length}/140',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: memoCtrl,
                      maxLength: 140,
                      maxLines: 2,
                      minLines: 1,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Memo note (max 140 chars)…',
                        hintStyle:
                            const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor:
                            Colors.white.withValues(alpha: 0.06),
                        counterText: '',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                      ),
                      onChanged: (v) {
                        edit.memo = v;
                        setD(() {});
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Private',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Switch(
                            value: edit.isPrivate,
                            activeThumbColor: green,
                            onChanged: (v) =>
                                setD(() => edit.isPrivate = v)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  deleteButton,
                ],
              ],
            );
          }

          Widget trackerBubble({
            required String title,
            required String? connectedLabel,
            required _TrackerEdit edit,
            required bool showDates,
            required bool showMemo,
            required Widget? deleteButton,
            required VoidCallback onConnect,
          }) {
            return GlassSurface(
              radius: 22,
              fill: const Color(0x40000000),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800))),
                        if (connectedLabel == null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: amber.withValues(alpha: 0.6)),
                              color: amber.withValues(alpha: 0.12),
                            ),
                            child: const Text('NOT CONNECTED',
                                style: TextStyle(
                                    color: amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          )
                        else
                          Text(connectedLabel,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    if (connectedLabel == null) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onConnect,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(999)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 15),
                          ),
                          child: const Text('Connect',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text('Status',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                          const Spacer(),
                          statusPill(edit),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Watched episodes',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          stepBtn(
                              Icons.remove,
                              edit.progress > 0
                                  ? () => setD(() => edit.progress--)
                                  : null),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 56,
                            child: Text(
                                '${edit.progress}/${total > 0 ? total : '—'}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          stepBtn(
                              Icons.add,
                              edit.progress < maxAllowed
                                  ? () => setD(() => edit.progress++)
                                  : null),
                        ],
                      ),
                      const SizedBox(height: 6),
                      thickSlider(
                        value: edit.progress.toDouble(),
                        max: maxAllowed.toDouble(),
                        divisions: maxAllowed,
                        onChanged: (v) =>
                            setD(() => edit.progress = v.round()),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Score',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                          const Spacer(),
                          Text(
                              '${edit.score.toStringAsFixed(1)}/10',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      thickSlider(
                        value: edit.score,
                        max: 10,
                        divisions: 20,
                        onChanged: (v) => setD(() =>
                            edit.score = (v * 2).round() / 2),
                      ),
                      const SizedBox(height: 4),
                      advancedSection(
                        edit: edit,
                        showDates: showDates,
                        showMemo: showMemo,
                        deleteButton:
                            deleteButton ?? const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28)),
            child: GlassSurface(
              radius: 28,
              fill: const Color(0x4D000000),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Anime Tracking',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800)),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(dCtx).pop(),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white
                                  .withValues(alpha: 0.08),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.16)),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _anime.cover.isNotEmpty
                              ? GaImage(
                                  url: _anime.cover,
                                  width: 56,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  errorFallback: Container(
                                    width: 56,
                                    height: 76,
                                    color: const Color(0xFF25262C),
                                    child: const Icon(Icons.image,
                                        size: 24, color: Colors.white24),
                                  ),
                                )
                              : Container(
                                  width: 56,
                                  height: 76,
                                  color: const Color(0xFF25262C)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: green.withValues(
                                          alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border: Border.all(
                                          color: green, width: 1),
                                    ),
                                    child: const Text('Tracker Tool',
                                        style: TextStyle(
                                            color: green,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.w700)),
                                  ),
                                  if (_anime.score != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                        '★ ${(_anime.score! / 10).toStringAsFixed(1)}',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w700)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(_anime.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    trackerBubble(
                      title: 'AniList Tracking',
                      connectedLabel: alConnected
                          ? (alName.isNotEmpty
                              ? '@$alName'
                              : 'Connected')
                          : null,
                      edit: alEdit,
                      showDates: true,
                      showMemo: false,
                      onConnect: () => connectTracker(setD, 'anilist'),
                      deleteButton:
                          (alConnected && alMediaId > 0)
                              ? deleteBtn('AniList',
                                  () => Trackers.anilistDeleteEntry(
                                      alToken, alMediaId))
                              : null,
                    ),
                    const SizedBox(height: 12),
                    trackerBubble(
                      title: 'Simkl Tracking',
                      connectedLabel: skConnected
                          ? (skName.isNotEmpty
                              ? '@$skName'
                              : 'Connected')
                          : null,
                      edit: skEdit,
                      showDates: false,
                      showMemo: true,
                      onConnect: () => connectTracker(setD, 'simkl'),
                      deleteButton: (skConnected && sId != null)
                          ? deleteBtn(
                              'Simkl',
                              () => Trackers.simklDeleteEntry(
                                  skClient, skToken, sId))
                          : null,
                    ),
                    const SizedBox(height: 12),
                    trackerBubble(
                      title: 'MyAnimeList Tracking',
                      connectedLabel: malConnected
                          ? (malUser.isNotEmpty
                              ? '@$malUser'
                              : 'Connected')
                          : null,
                      edit: malEdit,
                      showDates: true,
                      showMemo: false,
                      onConnect: () => connectTracker(setD, 'mal'),
                      deleteButton: (malConnected &&
                              mId != null &&
                              mId > 0)
                          ? deleteBtn(
                              'MyAnimeList',
                              () => Trackers.malDeleteEntry(
                                  malToken, mId))
                          : null,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dCtx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                  color: Colors.white
                                      .withValues(alpha: 0.15)),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(999)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                            child: const Text('Close',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => saveAll(dCtx),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(999)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                            child: const Text('Save Progress',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
                    child: _epThumb(ep).isNotEmpty
                        ? GaImage(
                            url: _epThumb(ep),
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

  /// Episode thumbnail with fallback chain: still -> banner -> cover -> ''.
  String _epThumb(EpisodeInfo ep) {
    if (ep.still.isNotEmpty) return ep.still;
    if (_anime.banner.isNotEmpty) return _anime.banner;
    return _anime.cover;
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
                    child: _epThumb(ep).isNotEmpty
                        ? GaImage(
                            url: _epThumb(ep),
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
    final a = _anime;
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
                // Height adapts to the banner's REAL aspect ratio — Kitsu
                // coverImages range from square-ish to cinemascope, and a
                // fixed-height BoxFit.cover hero cropped heads off or
                // letterboxed black depending on the title.
                // Banner fallback: never render the black header — fall back
                // to the cover image when no banner exists.
                if (a.banner.isNotEmpty)
                  _AspectHero(url: a.banner)
                else if (a.cover.isNotEmpty)
                  _AspectHero(url: a.cover)
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
                                  const Expanded(
                                    child: Text('Watching Progress',
                                        style: TextStyle(
                                            color: Color(0xFF9CA3AF),
                                            fontSize: 14)),
                                  ),
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
                                    onPressed: _showTrackingDialog,
                                    icon: const Icon(Icons.settings,
                                        size: 16),
                                    label: const Text('Tracking'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('$count / $total',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
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
          // Darkened + bordered for contrast when scrolled over content.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: CircleBorder(
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1),
                  ),
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


/// Full-width hero whose height matches the image's actual aspect ratio
/// (clamped). Resolves the image stream once, then animates to the right
/// height — no cropped heads, no black letterbox, whatever shape Kitsu's
/// coverImage comes in.
class _AspectHero extends StatefulWidget {
  final String url;
  const _AspectHero({required this.url});

  @override
  State<_AspectHero> createState() => _AspectHeroState();
}

class _AspectHeroState extends State<_AspectHero> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    NetworkImage(widget.url)
        .resolve(const ImageConfiguration())
        .addListener(
      ImageStreamListener(
        (info, _) {
          if (!mounted ||
              info.image.width == 0 ||
              info.image.height == 0) {
            return;
          }
          setState(() => _aspect = info.image.width / info.image.height);
        },
        onError: (_, _) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = _aspect == null
        ? 200.0
        // Fill the width; grow/shrink with the image's real shape.
        // Floor 200 keeps layout stable before/while loading; the cap
        // keeps square-ish banners from eating the whole screen.
        : (w / _aspect!).clamp(200.0, w * 0.72);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: h,
      width: double.infinity,
      child: GaImage(
        url: widget.url,
        height: h,
        width: double.infinity,
        fit: BoxFit.cover,
        errorFallback: Container(
            height: 200, color: GaColors.of(context).card),
      ),
    );
  }
}
