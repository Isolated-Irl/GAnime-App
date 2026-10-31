// Streams screen — website parity for the stream-fetch page.
// UI: header with framed poster + counts, circular back/refresh buttons,
// per-addon tabs, and rich stream CARDS (kind icon, addon, quality chip,
// source, seeders, size, filename, language info line, audio badge)
// with Play + Copy actions — instead of the old raw-text wall.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../store.dart';
import '../widgets/glass_surface.dart';
import '../widgets/player_panels.dart' show parseStreamInfo;
import 'player.dart';

class StreamsScreen extends StatefulWidget {
  final Anime anime;
  final int episode;
  final String profileId;
  final AppSettings settings;
  final Future<void> Function()? onMarkWatched;
  final List<EpisodeInfo>? episodes;     // -> player episode list
  final Set<int>? watchedEpisodes;      // -> player watched marks
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
  String? note; // "Asked as ..." / "No compatible ID ..." / error
  bool done = false;
  _Group(this.addon);
}

/// Torrentio-style description parsed into card pieces
/// (website parseStreamDesc port).
class _Desc {
  String file = '';
  String seeders = '';
  String size = '';
  String source = '';
  List<String> info = [];
}

_Desc _parseDesc(StreamSource s) {
  final d = _Desc();
  final lines = s.quality
      .split('\n')
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toList();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.contains('👤') || line.contains('💾') || line.contains('⚙')) {
      final seed = RegExp(r'👤\s*([\d,]+)').firstMatch(line);
      final size = RegExp(r'💾\s*([\d.]+\s*[KMGT]B)', caseSensitive: false)
          .firstMatch(line);
      final src = RegExp(r'⚙\s*([A-Za-z0-9._-]+)').firstMatch(line);
      if (seed != null) d.seeders = seed.group(1)!;
      if (size != null) d.size = size.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
      if (src != null && d.source.isEmpty) d.source = src.group(1)!;
    } else if (i == 0 && d.file.isEmpty) {
      d.file = line;
    } else {
      d.info.add(line);
    }
  }
  // Fallback: single-line description with no meta -> use stream name.
  if (d.file.isEmpty && lines.isEmpty) d.file = s.name;
  return d;
}

class _StreamsScreenState extends State<StreamsScreen> {
  final List<_Group> _groups = [];
  bool _loading = true;
  Object _tab = 'all'; // 'all' or _Group index

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _groups.clear();
      _loading = true;
      _tab = 'all';
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
      // Heal legacy records (no types/idPrefixes) once per load.
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
      // ID bridge with a hard cap.
      final fallback = AddonIds(kitsu: '${widget.anime.id}');
      final ids = await Future.any([
        AddonIdResolver.resolve(widget.anime),
        Future<AddonIds>.delayed(const Duration(seconds: 6), () => fallback),
      ]);
      if (!mounted) return;

      final isMovie = widget.anime.format.toUpperCase() == 'MOVIE';
      await Future.wait(addons.map((addon) async {
        final g = _Group(addon);
        _groups.add(g);
        if (mounted) setState(() {});
        try {
          final type = AddonsService.streamTypeFor(addon, isMovie);
          final sids = AddonIdResolver.streamIdsFor(
            addon, ids,
            title: widget.anime.title,
            isMovie: isMovie,
            episode: widget.episode,
          );
          if (sids.isEmpty) {
            g.note = 'No compatible ID — understands: '
                '${addon.idPrefixes.isEmpty ? "any" : addon.idPrefixes.join(", ")}';
          } else {
            g.note = 'Asked as ${sids.join(" · ")}';
            final seen = <String>{};
            for (final sid in sids) {
              try {
                for (final x in await AddonsService.streams(addon, type, sid)) {
                  if (x.url.isNotEmpty && seen.add(x.url)) g.streams.add(x);
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _header(a),
            if (_groups.isNotEmpty) _tabs(),
            Expanded(
              child: _groups.isEmpty
                  ? Center(
                      child: _loading
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 12),
                                Text('Asking your addons…',
                                    style: TextStyle(color: Colors.white70)),
                              ],
                            )
                          : const Text('No streaming addons installed.',
                              style: TextStyle(color: Colors.white70)),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF1B1B1F),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        children: [
                          for (var i = 0; i < _groups.length; i++)
                            if (_tab == 'all' || _tab == i) _groupBlock(_groups[i]),
                          if (!_loading && _total == 0)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                  child: Text('No streams found for this episode.',
                                      style: TextStyle(color: Colors.white54))),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Anime a) {
    // v3.1: buttons on their own top row (back left, refresh right),
    // poster + description on the row below — per the reference mockup.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassButton(
                  icon: Icons.arrow_back,
                  size: 40,
                  iconSize: 20,
                  circle: true,
                  onTap: () => Navigator.pop(context)),
              const Spacer(),
              GlassButton(
                icon: Icons.refresh,
                size: 40,
                iconSize: 20,
                circle: true,
                onTap: _loading ? null : _load,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.cover.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0x33FFFFFF), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x3300E676),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(a.cover,
                        width: 96,
                        height: 136,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const SizedBox(width: 96, height: 136)),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '${a.format.toUpperCase() == 'MOVIE' ? 'Movie' : 'Season 1 · Episode ${widget.episode}'} · ${a.year} · ★ ${a.score}',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _loading
                            ? 'Asking your addons…'
                            : '$_total streams from ${_groups.length} addons',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _tabChip('All · $_total', _tab == 'all', () => setState(() => _tab = 'all')),
          for (var i = 0; i < _groups.length; i++)
            _tabChip(
              _groups[i].done
                  ? '${_groups[i].addon.name} · ${_groups[i].streams.length}'
                  : '${_groups[i].addon.name} …',
              _tab == i,
              () => setState(() => _tab = i),
            ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GlassSurface(
        radius: 10,
        fill: active ? const Color(0x3300E676) : const Color(0x0DFFFFFF),
        border: active ? const Color(0x5900E676) : const Color(0x26FFFFFF),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      color: active ? const Color(0xFF00E676) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupBlock(_Group g) {
    // Addon name header + "Asked as …" note removed by design (v3):
    // the tab row already identifies the addon, so groups render
    // as plain card lists.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        for (final s in g.streams) _streamCard(g, s),
      ],
    );
  }

  Widget _streamCard(_Group g, StreamSource s) {
    final d = _parseDesc(s);
    final tags = parseStreamInfo(s).tags;
    final res = tags.where((t) => RegExp(r'P$').hasMatch(t)).firstOrNull ?? '';
    final audio = tags.where((t) =>
        RegExp(r'^(FLAC|TRUEHD|DTS|AC3|EAC3|AAC|OPUS)', caseSensitive: false).hasMatch(t)).firstOrNull;

    Color qColor = Colors.white70;
    if (RegExp(r'2160P|4K').hasMatch(res)) qColor = const Color(0xFFFACC15);
    if (res == '1080P') qColor = const Color(0xFF60A5FA);
    if (res == '720P') qColor = const Color(0xFF9CA3AF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: kind · addon · quality · source · seeders · size
              Row(
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(s.name.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (res.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(res,
                        style: TextStyle(
                            color: qColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (d.source.isNotEmpty)
                    _meta('⚙ ${d.source}'),
                  if (d.seeders.isNotEmpty)
                    _meta('👤 ${d.seeders}'),
                  if (d.size.isNotEmpty)
                    _meta('💾 ${d.size}'),
                  if (audio != null)
                    _meta(audio, color: const Color(0xFF4ADE80)),
                ],
              ),
              // Filename
              if (d.file.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(d.file,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
              // Info line (languages etc.)
              if (d.info.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(d.info.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
              ],
              const SizedBox(height: 10),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: GlassSurface(
                      radius: 10,
                      fill: const Color(0x3300E676),
                      border: const Color(0x5900E676),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => _play(g, s),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 9),
                            child: Center(
                              child: Text('▶ Play',
                                  style: TextStyle(
                                      color: Color(0xFF00E676),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassSurface(
                    radius: 10,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () => _copy(s.url),
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          child: Text('Copy',
                              style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String text, {Color color = Colors.white70}) {
    return Text(text, style: TextStyle(color: color, fontSize: 11.5));
  }

  void _play(_Group g, StreamSource s) {
    final selectedIdx = g.streams.indexOf(s);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          anime: widget.anime,
          episode: widget.episode,
          streams: g.streams,
          initialIndex: selectedIdx >= 0 ? selectedIdx : 0,
          settings: widget.settings,
          onMarkWatched: widget.onMarkWatched,
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
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }
}
