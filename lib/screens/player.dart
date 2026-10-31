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
  List<double> _chapters = []; // 0..1 ratios from mpv chapter-list
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
      // Generous forward cache: torrent swarms are slow and bursty; small
      // buffers = constant underrun = "heavy" stutter. mpvKt-class players
      // cache far more than this. (OOM was only ever a hypothesis — the
      // crash turned out to be the open-race, not memory.)
      await platform.setProperty('demuxer-max-bytes', '64MiB');
      await platform.setProperty('demuxer-max-back-bytes', '32MiB');
      await platform.setProperty('demuxer-readahead-secs', '10');
      // If the GPU/compositor falls behind, DROP late frames instead of
      // letting latency pile up — this is what makes VLC feel "light".
      await platform.setProperty('framedrop', 'vo');
      await platform.setProperty('vd-lavc-framedrop', 'nonkey');
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
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64MB stream buffer — absorbs torrent swarm bursts
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
    _loadChapters(); // Fetch chapter markers for seekbar breaks.
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

  /// Fetch chapter list from mpv for seekbar breaks (mpvKt style).
  /// Chapters come from the video file's embedded metadata.
  Future<void> _loadChapters() async {
    try {
      final dynamic platform = _player.platform;
      final list = await platform.getProperty('chapter-list');
      if (list is List && mounted) {
        final dur = _player.state.duration.inMilliseconds;
        if (dur > 0) {
          final ratios = <double>[];
          for (final c in list) {
            if (c is Map) {
              final time = (c['time'] as num?)?.toDouble();
              if (time != null && time > 0) {
                ratios.add((time * 1000 / dur).clamp(0.0, 1.0));
              }
            }
          }
          setState(() => _chapters = ratios);
        }
      }
    } catch (_) {
      // Chapters are optional — no breaks if unavailable.
    }
  }

  Future<void> _openCurrent() async {
    if (widget.streams.isEmpty) {
      setState(() => _status = 'No streams. Install an addon (Settings > Addons).');
      return;
    }
    final src = _cur;
    _autoSelected = false;
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
      // mpvKt-style: Fit Screen -> Stretch -> Crop
      _fit = switch (_fit) {
        BoxFit.contain => BoxFit.fill,
        BoxFit.fill => BoxFit.cover,
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
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(audio ? 'Audio tracks' : 'Subtitle tracks',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            // Clock → delay panel (subtitle or audio).
            IconButton(
              icon: const Icon(Icons.access_time, color: Colors.white70, size: 20),
              tooltip: audio ? 'Audio delay' : 'Subtitle delay',
              onPressed: () {
                Navigator.pop(context);
                if (audio) {
                  _showAudioDelay();
                } else {
                  _showSubtitleDelay();
                }
              },
            ),
            // Gear → style settings (subtitles only).
            if (!audio)
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
                tooltip: 'Subtitle settings',
                onPressed: () {
                  Navigator.pop(context);
                  _showSubtitleSettings();
                },
              ),
          ],
        ),
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

  Future<void> _setMpvProp(String key, dynamic value) async {
    try {
      final dynamic platform = _player.platform;
      await platform.setProperty(key, value);
    } catch (_) {}
  }

  /// Subtitle style settings (mpvKt-style): Typography, Colors, Miscellaneous.
  void _showSubtitleSettings() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassSurface(
          radius: 18,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: _SubtitleSettingsPanel(
              onSet: _setMpvProp,
            ),
          ),
        ),
      ),
    );
  }

  /// Subtitle delay with Voice heard / Text seen auto-sync.
  void _showSubtitleDelay() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassSurface(
          radius: 18,
          child: _DelayPanel(
            title: 'Subtitle delay',
            onSet: (v) => _setMpvProp('sub-delay', v),
            getPosition: () => _player.state.position.inMilliseconds / 1000.0,
            heardLabel: 'Voice heard',
            seenLabel: 'Text seen',
          ),
        ),
      ),
    );
  }

  /// Audio delay with Sound heard / Sound spotted auto-sync.
  void _showAudioDelay() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassSurface(
          radius: 18,
          child: _DelayPanel(
            title: 'Audio delay',
            onSet: (v) => _setMpvProp('audio-delay', v),
            getPosition: () => _player.state.position.inMilliseconds / 1000.0,
            heardLabel: 'Sound heard',
            seenLabel: 'Sound spotted',
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
            chapters: _chapters,
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

/// Subtitle style settings panel (mpvKt-style).
/// Sections: Typography, Colors, Miscellaneous.
class _SubtitleSettingsPanel extends StatefulWidget {
  final Future<void> Function(String key, dynamic value) onSet;
  const _SubtitleSettingsPanel({required this.onSet});

  @override
  State<_SubtitleSettingsPanel> createState() => _SubtitleSettingsPanelState();
}

class _SubtitleSettingsPanelState extends State<_SubtitleSettingsPanel> {
  bool _typographyOpen = true;
  bool _colorsOpen = false;
  bool _miscOpen = false;

  // Typography state
  bool _bold = false;
  bool _italic = false;
  String _align = 'center'; // left/center/right
  double _fontSize = 55;
  double _borderSize = 3;
  double _shadowOffset = 0;
  int _borderStyle = 1; // 0=none, 1=outline+shadow, 2=opaque box

  // Colors state (0-255)
  int _r = 255, _g = 255, _b = 255, _a = 255;

  // Misc state
  bool _assOverride = false;
  double _scale = 1.0;
  double _position = 100;

  Widget _sectionHeader(String title, bool open, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text('$label\n${value.toStringAsFixed(value < 10 ? 1 : 0)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorSlider(String label, int value, Color activeColor,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label\n$value',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              activeColor: activeColor,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  String get _colorHex =>
      '#${_r.toRadixString(16).padLeft(2, '0')}${_g.toRadixString(16).padLeft(2, '0')}${_b.toRadixString(16).padLeft(2, '0')}${_a.toRadixString(16).padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Subtitle settings',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // ---------- Typography ----------
          _sectionHeader('Typography', _typographyOpen,
              () => setState(() => _typographyOpen = !_typographyOpen)),
          if (_typographyOpen) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _styleBtn(Icons.format_bold, _bold, () {
                    setState(() => _bold = !_bold);
                    widget.onSet('sub-bold', _bold ? 'yes' : 'no');
                  }),
                  const SizedBox(width: 8),
                  _styleBtn(Icons.format_italic, _italic, () {
                    setState(() => _italic = !_italic);
                    widget.onSet('sub-italic', _italic ? 'yes' : 'no');
                  }),
                  const SizedBox(width: 16),
                  _alignBtn(Icons.format_align_left, _align == 'left', () {
                    setState(() => _align = 'left');
                    widget.onSet('sub-align-x', 'left');
                  }),
                  _alignBtn(Icons.format_align_center, _align == 'center', () {
                    setState(() => _align = 'center');
                    widget.onSet('sub-align-x', 'center');
                  }),
                  _alignBtn(Icons.format_align_right, _align == 'right', () {
                    setState(() => _align = 'right');
                    widget.onSet('sub-align-x', 'right');
                  }),
                ],
              ),
            ),
            _sliderRow('Font size', _fontSize, 10, 100, (v) {
              setState(() => _fontSize = v);
              widget.onSet('sub-font-size', v);
            }),
            _sliderRow('Border size', _borderSize, 0, 10, (v) {
              setState(() => _borderSize = v);
              widget.onSet('sub-border-size', v);
            }),
            _sliderRow('Shadow offset', _shadowOffset, 0, 10, (v) {
              setState(() => _shadowOffset = v);
              widget.onSet('sub-shadow-offset', v);
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Border style',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _borderStyle,
                    dropdownColor: const Color(0xFF2A2B30),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('None')),
                      DropdownMenuItem(value: 1, child: Text('Outline + shadow')),
                      DropdownMenuItem(value: 2, child: Text('Opaque box')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _borderStyle = v);
                        widget.onSet('sub-border-style', v.toString());
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
          const Divider(color: Colors.white12, height: 1),
          // ---------- Colors ----------
          _sectionHeader('Colors', _colorsOpen,
              () => setState(() => _colorsOpen = !_colorsOpen)),
          if (_colorsOpen) ...[
            _colorSlider('Red', _r, Colors.red, (v) {
              setState(() => _r = v.toInt());
              widget.onSet('sub-color', _colorHex);
            }),
            _colorSlider('Green', _g, Colors.green, (v) {
              setState(() => _g = v.toInt());
              widget.onSet('sub-color', _colorHex);
            }),
            _colorSlider('Blue', _b, Colors.blue, (v) {
              setState(() => _b = v.toInt());
              widget.onSet('sub-color', _colorHex);
            }),
            _colorSlider('Alpha', _a, Colors.white, (v) {
              setState(() => _a = v.toInt());
              widget.onSet('sub-color', _colorHex);
            }),
          ],
          const Divider(color: Colors.white12, height: 1),
          // ---------- Miscellaneous ----------
          _sectionHeader('Miscellaneous', _miscOpen,
              () => setState(() => _miscOpen = !_miscOpen)),
          if (_miscOpen) ...[
            SwitchListTile(
              title: const Text('Override ASS/SSA subtitles',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              value: _assOverride,
              onChanged: (v) {
                setState(() => _assOverride = v);
                widget.onSet('sub-ass-override', v ? 'force' : 'no');
              },
            ),
            _sliderRow('Scale', _scale, 0.1, 3.0, (v) {
              setState(() => _scale = v);
              widget.onSet('sub-scale', v);
            }),
            _sliderRow('Position', _position, 0, 100, (v) {
              setState(() => _position = v);
              widget.onSet('sub-pos', v);
            }),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _styleBtn(IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _alignBtn(IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: active ? Colors.white : Colors.white54, size: 20),
      ),
    );
  }
}

/// Delay panel with auto-sync (Voice heard / Text seen pattern).
class _DelayPanel extends StatefulWidget {
  final String title;
  final Future<void> Function(double value) onSet;
  final double Function() getPosition;
  final String heardLabel;
  final String seenLabel;
  const _DelayPanel({
    required this.title,
    required this.onSet,
    required this.getPosition,
    required this.heardLabel,
    required this.seenLabel,
  });

  @override
  State<_DelayPanel> createState() => _DelayPanelState();
}

class _DelayPanelState extends State<_DelayPanel> {
  double _delayMs = 0;
  double? _heardAt;
  double? _seenAt;

  void _apply(double ms) {
    setState(() => _delayMs = ms);
    widget.onSet(ms / 1000.0); // mpv uses seconds
  }

  void _tryAutoSync() {
    if (_heardAt != null && _seenAt != null) {
      // Heard at T1, saw at T2. If text came after voice (T2 > T1),
      // subtitles are late → negative delay to show earlier.
      final delayMs = (_heardAt! - _seenAt!) * 1000;
      _apply(delayMs.clamp(-10000, 10000));
      setState(() {
        _heardAt = null;
        _seenAt = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white70),
                onPressed: () => _apply(_delayMs - 50),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text('Delay',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 11)),
                    Text('${_delayMs.toInt()} ms',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.add_circle_outline, color: Colors.white70),
                onPressed: () => _apply(_delayMs + 50),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap one when you hear it, the other when you see it — delay is calculated automatically.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _heardAt = widget.getPosition());
                    _tryAutoSync();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _heardAt != null
                        ? Colors.green.shade700
                        : const Color(0xFF3A3B40),
                  ),
                  child: Text(widget.heardLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _seenAt = widget.getPosition());
                    _tryAutoSync();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _seenAt != null
                        ? Colors.green.shade700
                        : const Color(0xFF3A3B40),
                  ),
                  child: Text(widget.seenLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _apply(0),
            child: const Text('Reset to 0'),
          ),
        ],
      ),
    );
  }
}
