// Details + Episodes + Continue Watching entry point.
// Episodes come from ani.zip; watched state is local per profile.
// Tapping an episode opens the stream picker, then the player.
// If no addon is installed, streams are empty and the player screen
// explains that — the app never invents a stream source.
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/episodes.dart';
import '../services/addons.dart';
import '../store.dart';
import 'player.dart';

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

class _DetailsScreenState extends State<DetailsScreen> {
  List<EpisodeInfo> _episodes = [];
  Set<int> _watched = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final eps = await EpisodesService.forAnime(widget.anime);
      final w = await Store.watched(widget.profileId, widget.anime.id);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _watched = w;
          _loading = false;
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
    setState(() => _watched = next);
  }

  Future<void> _playEpisode(int ep) async {
    final addons = await Store.addons(widget.profileId);
    final streams = <StreamSource>[];
    for (final a in addons) {
      try {
        streams.addAll(await AddonsService.streams(
            a, 'anime', EpisodesService.streamIdFor(widget.anime, ep)));
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

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    final nextEp = _watched.isEmpty
        ? 1
        : (_watched.reduce((x, y) => x > y ? x : y) + 1);
    return Scaffold(
      appBar: AppBar(title: Text(a.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (a.banner.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(a.banner, height: 140, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(height: 140)),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.cover.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(a.cover, width: 110, height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 110)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('${a.format} • ${a.status}'
                        '${a.episodes != null ? ' • ${a.episodes} episodes' : ''}'
                        '${a.score != null ? ' • ★ ${a.score!.toStringAsFixed(0)}%' : ''}'),
                    if (a.genres.isNotEmpty)
                      Text(a.genres.join(', '),
                          style: TextStyle(color: Colors.grey.shade400)),
                    if (_watched.isNotEmpty)
                      Text('Continue: Episode $nextEp',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (a.description.isNotEmpty) Text(a.description),
          const SizedBox(height: 16),
          const Text('Episodes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_loading) const Padding(
              padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
          if (_error != null) Text('Episodes could not load: $_error'),
          for (final ep in _episodes)
            ListTile(
              leading: ep.still.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(ep.still, width: 72, height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.play_circle_outline)),
                    )
                  : const Icon(Icons.play_circle_outline),
              title: Text('EP ${ep.number}'
                  '${ep.title.isNotEmpty ? ' · ${ep.title}' : ''}'),
              subtitle: ep.overview.isNotEmpty ? Text(ep.overview, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
              trailing: IconButton(
                icon: Icon(
                  _watched.contains(ep.number)
                      ? Icons.visibility
                      : Icons.visibility_outlined,
                  color: _watched.contains(ep.number) ? Colors.green : null,
                ),
                onPressed: () => _toggleWatched(ep.number),
                tooltip: 'Mark watched / unwatch',
              ),
              onTap: () => _playEpisode(ep.number),
            ),
          if (!_loading && _episodes.isEmpty && _error == null)
            const Text('No episode list available for this title yet.'),
        ],
      ),
    );
  }
}
