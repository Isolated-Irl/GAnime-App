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
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/aniskip.dart';
import '../services/addons.dart';
import '../services/addon_ids.dart';
import '../services/resume_store.dart';
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

/// Local-only player preferences (SharedPreferences, never cloud-synced).
/// Holds the subtitle style map and the subtitle/audio delays, each gated
/// by its own opt-in "Remember across sessions" toggle.
class PlayerPrefs {
  static const _k = 'ganime_player_prefs';
  static SharedPreferences? _instance;

  static Future<SharedPreferences> get _p async =>
      _instance ??= await SharedPreferences.getInstance();

  static Future<Map<String, dynamic>> _all() async {
    final raw = (await _p).getString(_k);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<dynamic> get(String key) async => (await _all())[key];

  // Writes are chained so two quick set() calls can never read the same
  // old map and overwrite each other (that lost-update bug wiped the
  // "remember" flag right after it was saved).
  static Future<void> _queue = Future<void>.value();

  static Future<void> set(String key, dynamic value) {
    _queue = _queue.then((_) async {
      final m = await _all();
      m[key] = value;
      await (await _p).setString(_k, jsonEncode(m));
    }).catchError((_) {});
    return _queue;
  }
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

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
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
  Timer? _resumeTimer; // periodic backup save every 5s
  /// Guest profile ID: resume saves locally even without login.
  /// Logged-in users sync to cloud; guests stay on-device.
  static const _guestPid = 'guest';

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
      // Subtitle STYLE (size/colour/outline/position) is applied on the
      // our own overlay (see _subtitleOverlay), not on mpv.
      // Apply remembered subtitle / audio delays (these are mpv-side).
      try {
        if (await PlayerPrefs.get('remember_sub_delay') == true) {
          final ms = await PlayerPrefs.get('sub_delay_ms');
          if (ms is num) {
            await platform.setProperty('sub-delay', (ms / 1000.0).toString());
          }
        }
        if (await PlayerPrefs.get('remember_audio_delay') == true) {
          final ms = await PlayerPrefs.get('audio_delay_ms');
          if (ms is num) {
            await platform.setProperty('audio-delay', (ms / 1000.0).toString());
          }
        }
      } catch (_) {}
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

  // ---- Subtitle style (rendered by Flutter's SubtitleView) ----
  // Keys mirror the mpv names used by the settings panel ('sub-font-size'...).
  Map<String, String> _subStyle = {};

  Future<void> _loadSubStyle() async {
    try {
      // Remembering is ON unless the user explicitly switched it off.
      if (await PlayerPrefs.get('remember_sub_style') == false) return;
      final m = await PlayerPrefs.get('sub_style');
      if (m is Map && mounted) {
        setState(() => _subStyle =
            m.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
    } catch (_) {}
  }

  /// Called by the settings panel for every change: updates the live
  /// subtitle immediately.
  Future<void> _setSubStyle(String key, dynamic value) async {
    final String sv = (value is double && value.truncateToDouble() == value)
        ? value.toInt().toString()
        : value.toString();
    if (mounted) setState(() => _subStyle[key] = sv);
  }

  /// Settings > Playback > Subtitle Rendering supplies the defaults
  /// (size 10–30sp -> panel value sp*3 -> ~1.8px per sp); anything the user
  /// changed in the in-player panel overrides it until they press Reset.
  Map<String, String> _effectiveSubStyle() => {
        'sub-font-size': (widget.settings.subtitleSize * 3).round().toString(),
        ..._subStyle,
      };

  Future<void> _resetSubStyle() async {
    if (mounted) setState(() => _subStyle = {});
    await PlayerPrefs.set('sub_style', <String, String>{});
  }

  /// Our own subtitle renderer (replaces media_kit's SubtitleView, which
  /// silently shrinks text by sqrt(w*h / 1920*1080) ~ 0.4 on a phone — that is
  /// why "100" here only looked like "55" in mpvKt).
  ///
  /// Sizes follow mpv exactly: sub-font-size is in 720p-scaled pixels, so
  /// the real size = value * (screen height / 720). Value 55 here == 55 there.
  Widget _subtitleOverlay() {
    return LayoutBuilder(builder: (context, c) {
      final st = _effectiveSubStyle();
      double d(String k, double fb) => double.tryParse(st[k] ?? '') ?? fb;
      final k = c.maxHeight / 720.0;
      final fontPx = d('sub-font-size', 55) * d('sub-scale', 1.0) * k;
      final border = d('sub-border-size', 3) * k;
      final shadowOff = d('sub-shadow-offset', 0) * k;
      final borderStyle = int.tryParse(st['sub-border-style'] ?? '') ?? 1;
      final pos = d('sub-pos', 100).clamp(0.0, 100.0);

      var color = Colors.white;
      final cs = st['sub-color'] ?? '';
      if (cs.length >= 9 && cs.startsWith('#')) {
        final r = int.tryParse(cs.substring(1, 3), radix: 16) ?? 255;
        final g = int.tryParse(cs.substring(3, 5), radix: 16) ?? 255;
        final b = int.tryParse(cs.substring(5, 7), radix: 16) ?? 255;
        final a = int.tryParse(cs.substring(7, 9), radix: 16) ?? 255;
        color = Color.fromARGB(a, r, g, b);
      }

      final alignX = st['sub-align-x'];
      final textAlign = alignX == 'left'
          ? TextAlign.left
          : alignX == 'right'
              ? TextAlign.right
              : TextAlign.center;
      final boxAlign = alignX == 'left'
          ? Alignment.bottomLeft
          : alignX == 'right'
              ? Alignment.bottomRight
              : Alignment.bottomCenter;

      final base = TextStyle(
        fontSize: fontPx,
        height: 1.15,
        fontWeight:
            st['sub-bold'] == 'yes' ? FontWeight.w800 : FontWeight.w600,
        fontStyle:
            st['sub-italic'] == 'yes' ? FontStyle.italic : FontStyle.normal,
      );

      Widget label(String t) {
        final fill = Text(
          t,
          textAlign: textAlign,
          style: base.copyWith(
            color: color,
            shadows: (borderStyle == 1 && shadowOff > 0)
                ? [
                    Shadow(
                        color: Colors.black87,
                        offset: Offset(shadowOff, shadowOff),
                        blurRadius: shadowOff)
                  ]
                : null,
          ),
        );
        if (borderStyle == 2) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Color.fromRGBO(0, 0, 0,
                  widget.settings.subtitleBackgroundTint.clamp(0.0, 1.0)),
              borderRadius: BorderRadius.circular(4 * k),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 2 * k),
              child: fill,
            ),
          );
        }
        if (borderStyle == 1 && border > 0) {
          return Stack(
            children: [
              Text(
                t,
                textAlign: textAlign,
                style: base.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = border * 1.6
                    ..strokeJoin = StrokeJoin.round
                    ..color = Colors.black,
                ),
              ),
              fill,
            ],
          );
        }
        return fill;
      }

      return IgnorePointer(
        child: Align(
          alignment: boxAlign,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 0, 24, c.maxHeight * 0.06 + (100 - pos) / 100 * c.maxHeight * 0.8),
            child: StreamBuilder<List<String>>(
              stream: _player.stream.subtitle,
              initialData: _player.state.subtitle,
              builder: (_, snap) {
                final lines = (snap.data ?? const <String>[])
                    .where((l) => l.trim().isNotEmpty)
                    .toList();
                if (lines.isEmpty) return const SizedBox.shrink();
                return label(lines.join('\n'));
              },
            ),
          ),
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSubStyle();
    _loadFitMode();
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
    // Save the resume spot: every ~5s while playing, and on every pause.
    // Plus a periodic timer backup in case the position stream stalls.
    _player.stream.playing.listen((playing) {
      if (!playing) _saveResume(force: true);
    });
    _resumeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _player.state.playing) _saveResume();
    });
    _player.stream.position.listen((pos) async {
      _saveResume(); // throttled inside
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

  // ---------- Resume position (device + cloud) ----------
  int _lastResumeSaveMs = 0;
  bool _opening = false; // true while a new media is being opened

  /// Saves where you are. Safe to call often (throttled to every 5s unless
  /// [force]). Reads the player state BEFORE any await, so it is also safe
  /// to call from dispose().
  Future<void> _saveResume({bool force = false}) async {
    // Guest support: use 'guest' ID when not logged in. Saves locally;
    // cloud sync only happens for logged-in users (see requestCloudPush).
    final pid = widget.profileId ?? _guestPid;
    if (_opening) return;
    final animeId = widget.anime.id;
    final ep = _episode;
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (dur.inMilliseconds <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastResumeSaveMs < 5000) return;
    _lastResumeSaveMs = now;
    if (pos.inSeconds < 10) return; // never overwrite a real spot with ~0
    final remaining = dur.inMilliseconds - pos.inMilliseconds;
    if (pos.inMilliseconds / dur.inMilliseconds >= 0.95 || remaining < 90000) {
      await ResumeStore.clear(pid, animeId, ep); // finished
    } else {
      await ResumeStore.save(pid, animeId, ep, pos.inMilliseconds, dur.inMilliseconds);
    }
    // Only push to cloud for logged-in users; guests stay local.
    if (widget.profileId != null) {
      ResumeStore.requestCloudPush(); // throttled: max once a minute
    }
  }

  /// Saved spot for the CURRENT episode (3s rewind for context), or null.
  Future<Duration?> _resumeStart() async {
    final pid = widget.profileId ?? _guestPid;
    final e = await ResumeStore.get(pid, widget.anime.id, _episode);
    if (e == null || e.posMs < 10000) return null;
    return Duration(milliseconds: e.posMs) - const Duration(seconds: 3);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveResume(force: true).whenComplete(() {
        // Cloud push only for logged-in users.
        if (widget.profileId != null) {
          ResumeStore.requestCloudPush(force: true);
        }
      });
    }
  }

  Future<void> _openCurrent({bool keepPosition = false}) async {
    if (widget.streams.isEmpty) {
      setState(() => _status = 'No streams. Install an addon (Settings > Addons).');
      return;
    }
    final src = _cur;
    _autoSelected = false;
    // Switching source keeps the current time; a fresh episode resumes
    // from the saved spot (device or cloud).
    Duration? start;
    if (keepPosition) {
      final p = _player.state.position;
      if (p.inSeconds > 1) start = p;
    } else {
      start = await _resumeStart();
    }
    if (!mounted) return;
    setState(() => _status = start != null
        ? 'Resuming from ${fmtDuration(start)} …'
        : 'Opening ${src.name} …');
    _opening = true;
    try {
      await _enqueueOpen(() async {
        await _player.open(Media(src.url, start: start));
        await _player.play();
      });
    } finally {
      _opening = false;
    }
    if (mounted) {
      setState(() => _status = start != null
          ? 'Resumed from ${fmtDuration(start)}'
          : 'Playing ${src.name}');
    }
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
      await _saveResume(force: true); // save the episode we are leaving
      _episode = target;
      final jumpStart = await _resumeStart();
      _marked85 = false;
      _autoSelected = false;
      _loadSkips();
      setState(() => _status = 'Episode $target · ${hit.$1.name}');
      _opening = true;
      try {
        await _enqueueOpen(() async {
          await _player.open(Media(hit.$2.url, start: jumpStart));
          await _player.play();
        });
      } finally {
        _opening = false;
      }
    } finally {
      _jumping = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    // Leaving the player: save the spot (state is read synchronously inside),
    // then push it to the cloud (logged-in only).
    _saveResume(force: true).whenComplete(() {
      if (widget.profileId != null) {
        ResumeStore.requestCloudPush(force: true);
      }
    });
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
    // Remember across sessions (on by default, like subtitle style).
    PlayerPrefs.set('fit_mode', _fit.name);
  }

  /// Load the remembered fit mode (Fit/Stretch/Crop).
  Future<void> _loadFitMode() async {
    try {
      final saved = await PlayerPrefs.get('fit_mode') as String?;
      if (saved == null || !mounted) return;
      final fit = BoxFit.values.cast<BoxFit?>().firstWhere(
            (f) => f?.name == saved,
            orElse: () => null,
          );
      if (fit != null) setState(() => _fit = fit);
    } catch (_) {}
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
      // media_kit's setProperty takes a String; a raw double never reaches
      // mpv (type/cast error, silently swallowed). Also strip trailing ".0"
      // — mpv's integer options (sub-font-size, sub-pos) reject "55.0".
      final String s;
      if (value is double) {
        s = value.truncateToDouble() == value
            ? value.toInt().toString()
            : value.toString();
      } else {
        s = value.toString();
      }
      await platform.setProperty(key, s);
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
            constraints: const BoxConstraints(maxHeight: 560),
            child: _SubtitleSettingsPanel(
              onSet: _setSubStyle,
              onReset: _resetSubStyle,
              initial: Map<String, dynamic>.from(_effectiveSubStyle()),
            ),
          ),
        ),
      ),
    );
  }

  /// Subtitle delay with Voice heard / Text seen auto-sync.
  Future<void> _showSubtitleDelay() async {
    double initial = 0;
    if (await PlayerPrefs.get('remember_sub_delay') == true) {
      final ms = await PlayerPrefs.get('sub_delay_ms');
      if (ms is num) initial = ms.toDouble();
    }
    if (!mounted) return;
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
            persistKey: 'sub_delay_ms',
            rememberKey: 'remember_sub_delay',
            initialDelayMs: initial,
          ),
        ),
      ),
    );
  }

  /// Audio delay with Sound heard / Sound spotted auto-sync.
  Future<void> _showAudioDelay() async {
    double initial = 0;
    if (await PlayerPrefs.get('remember_audio_delay') == true) {
      final ms = await PlayerPrefs.get('audio_delay_ms');
      if (ms is num) initial = ms.toDouble();
    }
    if (!mounted) return;
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
            persistKey: 'audio_delay_ms',
            rememberKey: 'remember_audio_delay',
            initialDelayMs: initial,
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
      _openCurrent(keepPosition: true);
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
            subtitleViewConfiguration:
                const SubtitleViewConfiguration(visible: false),
          ),
          _subtitleOverlay(),
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
/// Values shown on open come from [initial] (the remembered style, if any);
/// the "Remember across sessions" switch opts into persisting changes.
class _SubtitleSettingsPanel extends StatefulWidget {
  final Future<void> Function(String key, dynamic value) onSet;
  final Map<String, dynamic> initial;
  final Future<void> Function() onReset;
  const _SubtitleSettingsPanel({
    required this.onSet,
    required this.onReset,
    this.initial = const <String, dynamic>{},
  });

  @override
  State<_SubtitleSettingsPanel> createState() => _SubtitleSettingsPanelState();
}

class _SubtitleSettingsPanelState extends State<_SubtitleSettingsPanel> {
  bool _typographyOpen = true;
  bool _colorsOpen = false;
  bool _miscOpen = false;

  // Typography state
  late bool _bold;
  late bool _italic;
  late String _align; // left/center/right
  late double _fontSize;
  late double _borderSize;
  late double _shadowOffset;
  late int _borderStyle; // 0=none, 1=outline+shadow, 2=opaque box

  // Colors state (0-255)
  late int _r, _g, _b, _a;

  // Misc state
  late double _scale;
  late double _position;

  // Persistence toggle
  late bool _remember;

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _bold = i['sub-bold'] == 'yes';
    _italic = i['sub-italic'] == 'yes';
    _align = (i['sub-align-x'] as String?) ?? 'center';
    _fontSize = _d(i['sub-font-size'], 55);
    _borderSize = _d(i['sub-border-size'], 3);
    _shadowOffset = _d(i['sub-shadow-offset'], 0);
    _borderStyle = int.tryParse('${i['sub-border-style'] ?? 1}') ?? 1;
    _r = _g = _b = _a = 255;
    final c = '${i['sub-color'] ?? ''}';
    if (c.length >= 9 && c.startsWith('#')) {
      _r = int.tryParse(c.substring(1, 3), radix: 16) ?? 255;
      _g = int.tryParse(c.substring(3, 5), radix: 16) ?? 255;
      _b = int.tryParse(c.substring(5, 7), radix: 16) ?? 255;
      _a = int.tryParse(c.substring(7, 9), radix: 16) ?? 255;
    }
    _scale = _d(i['sub-scale'], 1.0);
    _position = _d(i['sub-pos'], 100);
    _remember = true; // on by default; only off if the user turned it off
    PlayerPrefs.get('remember_sub_style').then((v) {
      if (mounted) setState(() => _remember = v != false);
    });
  }

  /// Current style as mpv-ready strings (also what gets persisted).
  Map<String, String> get _style => {
        'sub-bold': _bold ? 'yes' : 'no',
        'sub-italic': _italic ? 'yes' : 'no',
        'sub-align-x': _align,
        'sub-font-size': _fontSize.round().toString(),
        'sub-border-size': _fmt(_borderSize),
        'sub-shadow-offset': _fmt(_shadowOffset),
        'sub-border-style': '$_borderStyle',
        'sub-color': _colorHex,
        'sub-scale': _fmt(_scale),
        'sub-pos': _position.round().toString(),
      };

  Future<void> _save() => PlayerPrefs.set('sub_style', _style);

  /// Apply to the player now; persist only when remember is on.
  void _set(String key, dynamic value) {
    widget.onSet(key, value);
    if (_remember) _save();
  }

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
                TextButton(
                  onPressed: () async {
                    await widget.onReset();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Reset to Settings'),
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
                    _set('sub-bold', _bold ? 'yes' : 'no');
                  }),
                  const SizedBox(width: 8),
                  _styleBtn(Icons.format_italic, _italic, () {
                    setState(() => _italic = !_italic);
                    _set('sub-italic', _italic ? 'yes' : 'no');
                  }),
                  const SizedBox(width: 16),
                  _alignBtn(Icons.format_align_left, _align == 'left', () {
                    setState(() => _align = 'left');
                    _set('sub-align-x', 'left');
                  }),
                  _alignBtn(Icons.format_align_center, _align == 'center', () {
                    setState(() => _align = 'center');
                    _set('sub-align-x', 'center');
                  }),
                  _alignBtn(Icons.format_align_right, _align == 'right', () {
                    setState(() => _align = 'right');
                    _set('sub-align-x', 'right');
                  }),
                ],
              ),
            ),
            _sliderRow('Font size', _fontSize, 10, 100, (v) {
              setState(() => _fontSize = v);
              _set('sub-font-size', v.round());
            }),
            _sliderRow('Border size', _borderSize, 0, 10, (v) {
              setState(() => _borderSize = v);
              _set('sub-border-size', v);
            }),
            _sliderRow('Shadow offset', _shadowOffset, 0, 10, (v) {
              setState(() => _shadowOffset = v);
              _set('sub-shadow-offset', v);
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
                        _set('sub-border-style', v.toString());
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
              _set('sub-color', _colorHex);
            }),
            _colorSlider('Green', _g, Colors.green, (v) {
              setState(() => _g = v.toInt());
              _set('sub-color', _colorHex);
            }),
            _colorSlider('Blue', _b, Colors.blue, (v) {
              setState(() => _b = v.toInt());
              _set('sub-color', _colorHex);
            }),
            _colorSlider('Alpha', _a, Colors.white, (v) {
              setState(() => _a = v.toInt());
              _set('sub-color', _colorHex);
            }),
          ],
          const Divider(color: Colors.white12, height: 1),
          // ---------- Miscellaneous ----------
          _sectionHeader('Miscellaneous', _miscOpen,
              () => setState(() => _miscOpen = !_miscOpen)),
          if (_miscOpen) ...[
            _sliderRow('Scale', _scale, 0.1, 3.0, (v) {
              setState(() => _scale = v);
              _set('sub-scale', v);
            }),
            _sliderRow('Position', _position, 0, 100, (v) {
              setState(() => _position = v);
              _set('sub-pos', v.round());
            }),
          ],
          // ---------- Persistence ----------
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Remember across sessions',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: const Text('Save these subtitle settings for every video',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: _remember,
            onChanged: (v) {
              setState(() => _remember = v);
              PlayerPrefs.set('remember_sub_style', v);
              if (v) _save(); // capture the current style immediately
            },
          ),
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
  /// SharedPreferences keys for the opt-in "Remember across sessions"
  /// toggle: [persistKey] holds the delay in ms, [rememberKey] the bool.
  final String persistKey;
  final String rememberKey;
  final double initialDelayMs;
  const _DelayPanel({
    required this.title,
    required this.onSet,
    required this.getPosition,
    required this.heardLabel,
    required this.seenLabel,
    required this.persistKey,
    required this.rememberKey,
    this.initialDelayMs = 0,
  });

  @override
  State<_DelayPanel> createState() => _DelayPanelState();
}

class _DelayPanelState extends State<_DelayPanel> {
  late double _delayMs;
  double? _heardAt;
  double? _seenAt;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _delayMs = widget.initialDelayMs;
    PlayerPrefs.get(widget.rememberKey).then((v) {
      if (mounted) setState(() => _remember = v == true);
    });
  }

  void _apply(double ms) {
    setState(() => _delayMs = ms);
    widget.onSet(ms / 1000.0); // mpv uses seconds
    if (_remember) PlayerPrefs.set(widget.persistKey, ms);
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
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Remember across sessions',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text('Save this delay for every video',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            value: _remember,
            onChanged: (v) {
              setState(() => _remember = v);
              PlayerPrefs.set(widget.rememberKey, v);
              if (v) PlayerPrefs.set(widget.persistKey, _delayMs);
            },
          ),
          TextButton(
            onPressed: () => _apply(0),
            child: const Text('Reset to 0'),
          ),
        ],
      ),
    );
  }
}
