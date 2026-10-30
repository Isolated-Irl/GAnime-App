// Player screen — media_kit (mpv) with REX-style glass overlay controls.
// Features:
//  - Glass controls: tap toggle, double-tap ±10s (flash), auto-hide, lock
//  - Episodes panel (glass sheet, watched marks, jump in-place)
//  - Sources panel (rich cards: parsed tags/size/duration/flags, now playing)
//  - External player handoff (intent -> chooser -> copy link fallback)
//  - Next-episode jump: website jumpEpisode scoring ported
//    (same addon +100, release group +35, resolution +25, codec +10;
//     6s ID-bridge cap, 12s fetch cap), auto-advance on playback end
//  - 85% auto-mark, AniSkip (buttons + auto), audio/subtitle language
//    auto-select via track events, buffering spinner, orientation restore
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models.dart';
import '../services/aniskip.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../store.dart';
import '../widgets/glass_player_controls.dart';
import '../widgets/player_panels.dart';

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class PlayerScreen extends StatefulWidget {
  final Anime anime;
  final int episode;
  final List<StreamSource> streams;
  final AppSettings settings;
  final Future<void> Function()? onMarkWatched;

  // Optional — enable episode list / source switching / auto-next:
  final String? profileId;              // in-player episode jumping
  final List<EpisodeInfo>? episodes;      // episode list panel data
  final Set<int>? watchedEpisodes;      // watched marks
  final List<StreamSource>? allStreams;   // source switcher (the addon group)
  final String? addonId;                // scoring: prefer same addon
  final String? addonName;
  final int? totalEpisodes;             // anime.episodes

  const PlayerScreen({
    super.key,
    required this.anime,
    required this.episode,
    required this.streams,
    required this.settings,
    this.onMarkWatched,
    this.profileId,
    this.episodes,
    this.watchedEpisodes,
    this.allStreams,
    this.addonId,
    this.addonName,
    this.totalEpisodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static final _reRes =
      RegExp(r'2160p|4k|1440p|1080p|720p|480p', caseSensitive: false);
  static final _reGroup = RegExp(
      r'subsplease|erai-raws|judas|ember|asw|commie|horriblesubs|bilibili|crunchyroll',
      caseSensitive: false);
  static final _reCodec =
      RegExp(r'hevc|x265|avc|x264|av1', caseSensitive: false);

  late final Player _player;
  late final VideoController _controller;
  List<SkipInterval> _skips = [];
  bool _marked85 = false;
  bool _autoSelected = false;
  bool _jumping = false;
  int _streamIndex = 0;
  int _episode = 0;
  String _status = '';

  StreamSource get _cur => widget.streams[_streamIndex];

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.tracks.listen(_autoSelectTracks);
    _openCurrent();
    _loadSkips();
    _player.stream.position.listen((pos) async {
      final dur = _player.state.duration;
      if (dur.inMilliseconds <= 0 || _marked85) return;
      if (pos.inMilliseconds / dur.inMilliseconds >= 0.85) {
        _marked85 = true;
        if (widget.onMarkWatched != null) {
          try {
            await widget.onMarkWatched!();
          } catch (_) {}
        }
        if (mounted) {
          setState(() => _status = '85% reached — episode marked watched.');
        }
      }
      if (widget.settings.aniskipEnabled) {
        for (final s in _skips) {
          final auto = (s.kind == 'op' && widget.settings.aniskipAutoOp) ||
              (s.kind == 'ed' && widget.settings.aniskipAutoEd);
          if (!auto) continue;
          final t = pos.inMilliseconds / 1000;
          if (t >= s.start && t < s.end) {
            await _player.seek(Duration(milliseconds: (s.end * 1000).toInt()));
            break;
          }
        }
      }
    });
    // Auto-advance to the next episode on playback end.
    _player.stream.completed.listen((done) {
      if (!done || _jumping) return;
      final next = _episode + 1;
      if (widget.totalEpisodes == null || next <= widget.totalEpisodes!) {
        _jumpEpisode(next);
      }
    });
  }

  void _autoSelectTracks(Tracks tracks) {
    if (_autoSelected) return;
    if (tracks.audio.isEmpty && tracks.subtitle.isEmpty) return;
    _autoSelected = true;
    final audioLang = widget.settings.audioLanguage;
    if (audioLang.isNotEmpty) {
      for (final t in tracks.audio) {
        if ((t.language ?? '').toLowerCase().contains(audioLang.toLowerCase())) {
          _player.setAudioTrack(t);
          break;
        }
      }
    }
    final subLang = widget.settings.subtitleLanguage;
    if (subLang.isEmpty) {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      for (final t in tracks.subtitle) {
        if ((t.language ?? '').toLowerCase().contains(subLang.toLowerCase())) {
          _player.setSubtitleTrack(t);
          break;
        }
      }
    }
  }

  Future<void> _loadSkips() async {
    if (!widget.settings.aniskipEnabled) return;
    final skips = await AniSkip.fetch(
      widget.anime.malId,
      _episode,
      detectRecap: widget.settings.aniskipDetectRecap,
    );
    if (mounted) setState(() => _skips = skips);
  }

  Future<void> _openCurrent() async {
    if (widget.streams.isEmpty) {
      setState(() => _status = 'No streams. Install an addon (Settings > Addons).');
      return;
    }
    final src = _cur;
    _autoSelected = false;
    setState(() => _status = 'Opening ${src.name} …');
    await _player.open(Media(src.url));
    await _player.play();
    if (mounted) setState(() => _status = 'Playing ${src.name}');
  }

  /// Website jumpEpisode port: fetch target-episode streams from every
  /// addon (6s ID cap, 12s fetch cap) and open the best match by scoring
  /// the current stream's text (same addon > release group > res > codec).
  Future<void> _jumpEpisode(int target) async {
    if (_jumping || widget.profileId == null) return;
    if (widget.totalEpisodes != null && target > widget.totalEpisodes!) return;
    _jumping = true;
    setState(() => _status = 'Episode $target — fetching streams…');
    try {
      var addons = (await Store.addons(widget.profileId!))
          .where((a) => a.enabled)
          .toList();
      if (addons.isEmpty) {
        addons = (await Store.allAddons()).where((a) => a.enabled).toList();
      }
      final fallback = AddonIds(kitsu: '${widget.anime.id}');
      final ids = await Future.any([
        AddonIdResolver.resolve(widget.anime),
        Future<AddonIds>.delayed(const Duration(seconds: 6), () => fallback),
      ]);
      final isMovie = widget.anime.format.toUpperCase() == 'MOVIE';
      final prevText = '${_cur.name}\n${_cur.quality}'.toLowerCase();
      final prevRes = _reRes.firstMatch(prevText)?.group(0) ?? '';
      final prevGroup = _reGroup.firstMatch(prevText)?.group(0) ?? '';
      final prevCodec = _reCodec.firstMatch(prevText)?.group(0) ?? '';

      final fetchAll = Future.wait(addons.map((a) async {
        try {
          final type = AddonsService.streamTypeFor(a, isMovie);
          final sids = AddonIdResolver.streamIdsFor(
            a, ids,
            title: widget.anime.title,
            isMovie: isMovie,
            episode: target,
          );
          final seen = <String>{};
          final out = <StreamSource>[];
          for (final sid in sids) {
            for (final x in await AddonsService.streams(a, type, sid)) {
              if (x.url.isNotEmpty && seen.add(x.url)) out.add(x);
            }
          }
          return (a, out);
        } catch (_) {
          return (a, <StreamSource>[]);
        }
      }));
      final settled = await Future.any([
        fetchAll,
        Future<List<(AddonRecord, List<StreamSource>)>>.delayed(
            const Duration(seconds: 12), () => const []),
      ]);

      (AddonRecord, StreamSource)? best;
      var bestScore = -1;
      for (final entry in settled) {
        final a = entry.$1;
        for (final x in entry.$2) {
          final txt = '${x.name}\n${x.quality}'.toLowerCase();
          var score = 0;
          if (a.id == widget.addonId || a.name == widget.addonName) score += 100;
          if (prevGroup.isNotEmpty && txt.contains(prevGroup)) score += 35;
          if (prevRes.isNotEmpty && txt.contains(prevRes)) score += 25;
          if (prevCodec.isNotEmpty && txt.contains(prevCodec)) score += 10;
          if (score > bestScore) {
            bestScore = score;
            best = (a, x);
          }
        }
      }
      if (best == null) {
        setState(() => _status = 'No streams found for episode $target.');
        return;
      }
      final hit = best; // non-null after the check above
      _episode = target;
      _marked85 = false;
      _autoSelected = false;
      _loadSkips();
      setState(() => _status = 'Episode $target · ${hit.$1.name}');
      await _player.open(Media(hit.$2.url));
      await _player.play();
    } finally {
      _jumping = false;
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  void _showTracks() {
    final tracks = _player.state.tracks;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Audio tracks')),
          ListTile(
            title: const Text('Auto (default)'),
            onTap: () {
              _player.setAudioTrack(AudioTrack.auto());
              Navigator.pop(context);
            },
          ),
          for (final t in tracks.audio)
            ListTile(
              title: Text(t.title ?? t.id),
              subtitle: Text('language: ${t.language ?? 'unknown'} · id: ${t.id}'),
              onTap: () {
                _player.setAudioTrack(t);
                Navigator.pop(context);
              },
            ),
          const Divider(),
          const ListTile(title: Text('Subtitle tracks')),
          ListTile(
            title: const Text('Off'),
            onTap: () {
              _player.setSubtitleTrack(SubtitleTrack.no());
              Navigator.pop(context);
            },
          ),
          for (final t in tracks.subtitle)
            ListTile(
              title: Text(t.title ?? t.id),
              subtitle: Text('language: ${t.language ?? 'unknown'} · id: ${t.id}'),
              onTap: () {
                _player.setSubtitleTrack(t);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _showSources() async {
    final list = widget.allStreams ?? widget.streams;
    if (list.length < 2) return;
    final s = await showSourcesPanel(context,
        streams: list, nowPlayingUrl: _cur.url, addonName: widget.addonName ?? '');
    if (s != null && s.url != _cur.url && mounted) {
      final i = list.indexWhere((e) => e.url == s.url);
      setState(() => _streamIndex = i < 0 ? 0 : i);
      _openCurrent();
    }
  }

  Future<void> _showEpisodes() async {
    if (widget.episodes == null || widget.episodes!.isEmpty) return;
    final ep = await showEpisodesPanel(context,
        episodes: widget.episodes!,
        current: _episode,
        watched: widget.watchedEpisodes ?? const {});
    if (ep != null && ep != _episode) _jumpEpisode(ep);
  }

  Future<void> _openExternal() async {
    final r = await ExternalPlayer.launch(_cur.url);
    if (r == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied — paste it in your player')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fill: Colors.black,
          ),
          StreamBuilder<bool>(
            stream: _player.stream.buffering,
            initialData: true,
            builder: (_, snap) => (snap.data ?? false)
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const SizedBox.shrink(),
          ),
          GlassPlayerControls(
            player: _player,
            title: '${widget.anime.title} — EP $_episode',
            status: _status,
            skips: _skips,
            showSkipButtons:
                widget.settings.aniskipEnabled && widget.settings.aniskipShowButton,
            onBack: () => Navigator.of(context).maybePop(),
            onTracks: _showTracks,
            onSources: (widget.allStreams ?? widget.streams).length > 1
                ? _showSources
                : null,
            onEpisodes: (widget.episodes != null && widget.episodes!.isNotEmpty)
                ? _showEpisodes
                : null,
            onExternal: _openExternal,
            onNextEpisode: (widget.profileId != null &&
                    (widget.totalEpisodes == null ||
                        _episode < widget.totalEpisodes!))
                ? () => _jumpEpisode(_episode + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
