// Streams screen — website parity for the "Select Stream" flow.
//
// Opens INSTANTLY on episode tap (spinner + per-addon groups), resolves
// the ID bridge with a hard 6s cap, asks every enabled addon in PARALLEL
// (25s timeout each, patched into AddonsService.streams), renders each
// addon's streams as they answer, and only opens the player when the
// user taps a link. Replaces the old silent-fetch-then-autoplay-first
// behavior in details.dart.
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../store.dart';
import 'player.dart';

class StreamsScreen extends StatefulWidget {
  final Anime anime;
  final int episode;
  final String profileId;
  final AppSettings settings;
  final Future<void> Function()? onMarkWatched;
  final List<EpisodeInfo>? episodes;      // -> player episode list
  final Set<int>? watchedEpisodes;        // -> player watched marks
  const StreamsScreen({
    super.key,
    required this.anime,
    required this.episode,
    required this.profileId,
    required this.settings,
    this.onMarkWatched,
    this.episodes,
    this.watchedEpisodes,
  });

  @override
  State<StreamsScreen> createState() => _StreamsScreenState();
}

class _Group {
  final AddonRecord addon;
  final List<StreamSource> streams = [];
  String? note; // "Asked as ..." or "Could not fetch: ..." or no-id note
  bool done = false;
  _Group(this.addon);
}

class _StreamsScreenState extends State<StreamsScreen> {
  final List<_Group> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _groups.clear();
      _loading = true;
    });
    try {
      var addons = (await Store.addons(widget.profileId))
          .where((a) => a.enabled)
          .toList();
      if (addons.isEmpty) {
        addons = (await Store.allAddons()).where((a) => a.enabled).toList();
      }
      if (!mounted) return;
      if (addons.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      // Legacy records saved before types/idPrefixes existed: refetch the
      // manifest once so per-addon type + id dialects resolve (same
      // healing details.dart used to do before playing).
      for (var i = 0; i < addons.length; i++) {
        final a = addons[i];
        if (a.types.isEmpty) {
          try {
            final fresh = await AddonsService.fetchManifest(a.manifestUrl);
            final updated =
                a.copyWith(types: fresh.types, idPrefixes: fresh.idPrefixes);
            addons[i] = updated;
            final all = await Store.addons(widget.profileId);
            final idx = all.indexWhere((e) => e.manifestUrl == a.manifestUrl);
            if (idx >= 0) {
              all[idx] = updated;
              await Store.saveAddons(widget.profileId, all);
            }
          } catch (_) {}
        }
      }
      // ID bridge with a hard cap: a hung mapping service must never
      // freeze this screen. Details passes the normalized Kitsu object,
      // so the fallback dialect is already correct.
      final fallback = AddonIds(kitsu: '${widget.anime.id}');
      final ids = await Future.any([
        AddonIdResolver.resolve(widget.anime),
        Future<AddonIds>.delayed(const Duration(seconds: 6), () => fallback),
      ]);
      if (!mounted) return;

      final isMovie = widget.anime.format.toUpperCase() == 'MOVIE';
      // Ask every addon in parallel; each group updates the UI as it
      // answers (website allSettled + progressive render).
      await Future.wait(addons.map((addon) async {
        final g = _Group(addon);
        _groups.add(g);
        if (mounted) setState(() {});
        try {
          final type = AddonsService.streamTypeFor(addon, isMovie);
          final sids = AddonIdResolver.streamIdsFor(
            addon,
            ids,
            title: widget.anime.title,
            isMovie: isMovie,
            episode: widget.episode,
          );
          if (sids.isEmpty) {
            g.note = 'No compatible ID — understands: '
                '${addon.idPrefixes.join(', ')}';
          } else {
            g.note = 'Asked as ${sids.join(' · ')}';
            for (final sid in sids) {
              try {
                final found = await AddonsService.streams(addon, type, sid);
                for (final s in found) {
                  if (s.url.isNotEmpty) g.streams.add(s);
                }
              } catch (_) {}
            }
          }
        } catch (e) {
          g.note = 'Could not fetch: $e';
        }
        g.done = true;
        if (mounted) setState(() {});
      }));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Stream fetch failed: $e')));
      }
    }
  }

  int get _total => _groups.fold(0, (n, g) => n + g.streams.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Episode ${widget.episode} — Streams')),
      body: _groups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final g in _groups) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 18, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.addon.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall,
                            ),
                          ),
                          if (!g.done)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    if (g.note != null)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(g.note!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall),
                      ),
                    for (final s in g.streams)
                      ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.play_circle_outline),
                        title: Text(s.quality.isEmpty
                            ? s.name
                            : '${s.name} — ${s.quality}'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                anime: widget.anime,
                                episode: widget.episode,
                                streams: g.streams,
                                settings: widget.settings,
                                onMarkWatched: widget.onMarkWatched,
                                // full feature set:
                                profileId: widget.profileId,
                                episodes: widget.episodes,
                                watchedEpisodes: widget.watchedEpisodes,
                                allStreams: g.streams,
                                addonId: g.addon.id,
                                addonName: g.addon.name,
                                totalEpisodes: widget.anime.episodes,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                  if (_loading && _total == 0)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Asking addons…')),
                    ),
                  if (!_loading && _total == 0)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('No streams found for this episode.')),
                    ),
                ],
              ),
            ),
    );
  }
}
