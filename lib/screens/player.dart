// Player screen — media_kit (mpv). NOT movi, NOT a web view.
// Features: play/pause, seek bar with 85% marker + passed indicator,
// audio/subtitle track picker (language where mpv reports it),
// AniSkip buttons + auto-skip toggles from settings, 85% auto-mark
// (marks the episode watched locally and pushes to trackers via the
// caller's onMarkWatched callback; never un-marks, never for movies).
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models.dart';
import '../services/aniskip.dart';

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
  const PlayerScreen({
    super.key,
    required this.anime,
    required this.episode,
    required this.streams,
    required this.settings,
    this.onMarkWatched,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  List<SkipInterval> _skips = [];
  bool _marked85 = false;
  int _streamIndex = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
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
        if (mounted) setState(() => _status = '85% reached — episode marked watched.');
      }
      // Auto-skip: if inside an interval whose kind is auto-enabled, jump.
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
  }

  Future<void> _loadSkips() async {
    if (!widget.settings.aniskipEnabled) return;
    final skips = await AniSkip.fetch(
      widget.anime.malId,
      widget.episode,
      detectRecap: widget.settings.aniskipDetectRecap,
    );
    if (mounted) setState(() => _skips = skips);
  }

  Future<void> _openCurrent() async {
    if (widget.streams.isEmpty) {
      setState(() => _status = 'No streams. Install an addon (Settings > Addons) or use Player Test.');
      return;
    }
    final src = widget.streams[_streamIndex];
    setState(() => _status = 'Opening ${src.name} …');
    await _player.open(Media(src.url));
    await _player.play();
    // Auto-select audio/subtitle by language, separately.
    // media_kit tracks arrive after open; a short delay lets mpv report them.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final tracks = _player.state.tracks;
    final audioLang = widget.settings.audioLanguage;
    if (audioLang.isNotEmpty) {
      for (final t in tracks.audio) {
        if ((t.language ?? '').toLowerCase().contains(audioLang.toLowerCase())) {
          await _player.setAudioTrack(t);
          break;
        }
      }
    }
    final subLang = widget.settings.subtitleLanguage;
    if (subLang.isEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      for (final t in tracks.subtitle) {
        if ((t.language ?? '').toLowerCase().contains(subLang.toLowerCase())) {
          await _player.setSubtitleTrack(t);
          break;
        }
      }
    }
    if (mounted) setState(() => _status = 'Playing ${src.name}');
  }

  @override
  void dispose() {
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

  void _showSources() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (var i = 0; i < widget.streams.length; i++)
            ListTile(
              title: Text(widget.streams[i].name),
              subtitle: Text(widget.streams[i].quality),
              trailing: i == _streamIndex ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(context);
                setState(() => _streamIndex = i);
                _openCurrent();
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.anime.title} — EP ${widget.episode}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: _controller, controls: NoVideoControls),
          ),
          const SizedBox(height: 12),
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: _player.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final total = dur.inMilliseconds;
                  final p = pos.inMilliseconds.clamp(0, total);
                  final ratio = total > 0 ? p / total : 0.0;
                  final passed85 = total > 0 && ratio >= 0.85;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Slider(
                        value: total > 0 ? p.toDouble() : 0,
                        min: 0,
                        max: total > 0 ? total.toDouble() : 1,
                        onChanged: (v) =>
                            _player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${fmtDuration(pos)} / ${fmtDuration(dur)}'),
                          Chip(
                            label: Text(passed85 ? '85% passed ✓' : '◆ 85% marker'),
                            backgroundColor: passed85 ? Colors.green : null,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _player.playOrPause(),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    label: Text(playing ? 'Pause' : 'Play'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showTracks,
                    icon: const Icon(Icons.subtitles),
                    label: const Text('Audio / Subtitle tracks'),
                  ),
                  if (widget.streams.length > 1)
                    OutlinedButton(
                      onPressed: _showSources,
                      child: const Text('Sources'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (widget.settings.aniskipEnabled && widget.settings.aniskipShowButton)
            Wrap(
              spacing: 8,
              children: [
                for (final s in _skips)
                  OutlinedButton(
                    onPressed: () => _player.seek(
                        Duration(milliseconds: (s.end * 1000).toInt())),
                    child: Text('${s.label} (${s.start.toInt()}s → ${s.end.toInt()}s)'),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(_status),
          StreamBuilder<Tracks>(
            stream: _player.stream.tracks,
            builder: (context, snap) {
              final t = snap.data;
              if (t == null) return const Text('Tracks: not loaded yet.');
              return Text(
                  'Tracks — audio: ${t.audio.length}, subtitle: ${t.subtitle.length}, video: ${t.video.length}');
            },
          ),
        ],
      ),
    );
  }
}
