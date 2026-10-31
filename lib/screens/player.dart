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
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../services/aniskip.dart';
import '../services/app_logger.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../store.dart';
import '../widgets/glass_player_controls.dart';
import '../widgets/glass_surface.dart';
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
  final int initialIndex;
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
    this.initialIndex = 0,
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
  late bool _isHw; // active decoder: true = HW (MediaCodec), false = SW (CPU)

  /// Serializes every mpv open/reopen. Two overlapping Player.open() calls
  /// (toggle / source switch / next-ep while the previous demuxer is still
  /// tearing down) are a known native SIGSEGV trigger in mpv — queue instead.
  Future<void> _openChain = Future.value();
  bool _skipSeeking = false; // re-entrancy guard for AniSkip auto-seek
  BoxFit _fit = BoxFit.contain;

  StreamSource get _cur => widget.streams[_streamIndex];

  /// Sets mpv's native hwdec property ('mediacodec' = Android HW, 'no' = CPU SW).
  Future<void> _applyHwDecProperty(bool hw) async {
    final dynamic platform = _player.platform;
    try {
      // NEVER set 'vo' or 'framedrop' manually on Android.
      // media_kit_video manages the native SurfaceTexture context.
      await platform.setProperty('hwdec', hw ? 'mediacodec' : 'no');
    } catch (_) {}
  }

  /// Boot-time mpv setup: applies the decoder mode, bounds demuxer memory,
  /// and defers video open until the Android SurfaceTexture is attached.
  Future<void> _initMpvAndOpen() async {
    final dynamic platform = _player.platform;
    try {
      await platform.setProperty('hwdec', _isHw ? 'mediacodec' : 'no');
      // Tighter bounds: 32MB+16MB on top of the 32MB Player buffer was
      // enough to get low-RAM devices OOM-killed (SIGKILL looks exactly
      // like a "silent crash" in the app log).
      await platform.setProperty('demuxer-max-bytes', '16MiB');
      await platform.setProperty('demuxer-max-back-bytes', '8MiB');
      // Torrent-backed streams drop the connection mid-playback; make
      // libavformat reconnect instead of driving mpv into a bad state.
      await platform.setProperty(
          'stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      await platform.setProperty('network-timeout', '60');
    } catch (_) {}
    // Capture mpv's OWN log so the next native-side error is on disk
    // before the process dies (Dart handlers can't see native crashes).
    try {
      final dir = await getApplicationDocumentsDirectory();
      await platform.setProperty('log-file', '${dir.path}/mpv.log');
      await platform.setProperty('msg-level', 'all=info');
      AppLogger().log('PLAYER', 'mpv log -> ${dir.path}/mpv.log');
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openCurrent();
        _loadSkips();
      }
    });
  }

  /// Queues [task] behind any in-flight open so mpv never sees two
  /// concurrent opens. Errors don't break the chain.
  Future<void> _enqueueOpen(Future<void> Function() task) {
    final next = _openChain.then((_) => task());
    _openChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Toggles HW/SW decoding mid-playback. MediaCodec cannot hot-swap, so the
  /// stream is re-opened at the exact current position.
  Future<void> _toggleHwDec() async {
    if (widget.streams.isEmpty) return;
    final nextHw = !_isHw;
    final currentPos = _player.state.position;
    final isPlaying = _player.state.playing;
    setState(() {
      _isHw = nextHw;
      _status =
          nextHw ? 'Switching to Hardware (HW)...' : 'Switching to Software (SW)...';
    });
    await _applyHwDecProperty(nextHw);
    final src = _cur;
    AppLogger().log('PLAYER',
        'HW toggle -> ${nextHw ? 'HW' : 'SW'}, reopening at $currentPos');
    await _enqueueOpen(
        () => _player.open(Media(src.url, start: currentPos), play: isPlaying));
    if (mounted) {
      setState(() {
        _status = nextHw
            ? 'Decoder: HW (MediaCodec)'
            : 'Decoder: SW (Software CPU)';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _streamIndex = widget.initialIndex; // open the stream the user tapped
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _isHw = widget.settings.hardwareDecoding;
    AppLogger().log('PLAYER',
        'init: "${widget.anime.title}" ep ${widget.episode}, stream #${widget.initialIndex}, decoder=${_isHw ? 'HW' : 'SW'}');
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024, // 16MB stream buffer (32MB + big demuxer bounds got low-RAM phones OOM-killed)
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _player.stream.tracks.listen(_autoSelectTracks);
    // Catch stream failures gracefully instead of crashing.
    _player.stream.error.listen((err) {
      AppLogger().log('PLAYER', 'stream error: $err');
      if (mounted) setState(() => _status = 'Stream error: $err');
    });
    // Defer the video open until the Android surface is mounted (post-frame),
    // so the codec never starts before the SurfaceTexture exists.
    _initMpvAndOpen();
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
      if (widget.settings.aniskipEnabled && !_skipSeeking) {
        for (final s in _skips) {
          final auto = (s.kind == 'op' && widget.settings.aniskipAutoOp) ||
              (s.kind == 'ed' && widget.settings.aniskipAutoEd);
          if (!auto) continue;
          final t = pos.inMilliseconds / 1000;
          if (t >= s.start && t < s.end) {
            _skipSeeking = true;
            try {
              await _player
                  .seek(Duration(milliseconds: (s.end * 1000).toInt()));
            } catch (_) {}
            if (mounted) setState(() => _skipSeeking = false);
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
    AppLogger().log('PLAYER',
        'opening stream: ${AppLogger.urlLabel(src.url, src.quality)} (${src.name})');
    setState(() => _status = 'Opening ${src.name} …');
    await _enqueueOpen(() async {
      await _player.open(Media(src.url));
      await _player.play();
    });
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
      await _enqueueOpen(() async {
        await _player.open(Media(hit.$2.url));
        await _player.play();
      });
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

  Future<void> _cycleSpeed() async {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final cur = _player.state.rate;
    final next = rates.firstWhere((r) => r > cur + 0.001, orElse: () => 1.0);
    await _player.setRate(next);
    if (mounted) setState(() => _status = 'Speed ${next}x');
  }

  void _cycleFit() {
    setState(() {
      _fit = switch (_fit) {
        BoxFit.contain => BoxFit.cover,
        BoxFit.cover => BoxFit.fitWidth,
        _ => BoxFit.contain,
      };
    });
  }

  void _showAudio() => _trackPopup(audio: true);
  void _showSubs() => _trackPopup(audio: false);

  /// Small liquid-glass popup (VLC/MX style) anchored near the top-right,
  /// replacing the old full-width bottom sheet. Checkmark on the active
  /// track. Sources/Episodes panels are untouched (already glass).
  void _trackPopup({required bool audio}) {
    final tracks = _player.state.tracks;
    final activeId =
        audio ? _player.state.track.audio.id : _player.state.track.subtitle.id;

    Widget row({
      required String title,
      String? subtitle,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            onTap();
            Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      if (subtitle != null)
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
                if (active)
                  const Icon(Icons.check, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(audio ? 'Audio tracks' : 'Subtitle tracks',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ),
      row(
        title: audio ? 'Auto (default)' : 'Off',
        active: activeId == (audio ? 'auto' : 'no'),
        onTap: () {
          if (audio) {
            _player.setAudioTrack(AudioTrack.auto());
          } else {
            _player.setSubtitleTrack(SubtitleTrack.no());
          }
        },
      ),
      if (audio)
        for (final t in tracks.audio)
          row(
            title: t.title ?? t.id,
            subtitle: 'language: ${t.language ?? 'unknown'} · id: ${t.id}',
            active: t.id == activeId,
            onTap: () => _player.setAudioTrack(t),
          )
      else
        for (final t in tracks.subtitle)
          row(
            title: t.title ?? t.id,
            subtitle: 'language: ${t.language ?? 'unknown'} · id: ${t.id}',
            active: t.id == activeId,
            onTap: () => _player.setSubtitleTrack(t),
          ),
      const SizedBox(height: 8),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.topRight,
        insetPadding: const EdgeInsets.only(top: 76, right: 16, left: 16),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassSurface(
          radius: 16,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 320, maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
            ),
          ),
        ),
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
            fit: _fit,
            fill: Colors.black,
          ),
          GlassPlayerControls(
            player: _player,
            isHw: _isHw,
            onToggleHw: _toggleHwDec,
            title: '${widget.anime.title} — EP $_episode',
            status: _status,
            skips: _skips,
            showSkipButtons:
                widget.settings.aniskipEnabled && widget.settings.aniskipShowButton,
            onBack: () => Navigator.of(context).maybePop(),
            onAudio: _showAudio,
            onSubs: _showSubs,
            onCycleSpeed: _cycleSpeed,
            onCycleFit: _cycleFit,
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
