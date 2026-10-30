// Overlay controls for the media_kit player, styled with GlassSurface.
// Compact "glass pill" layout matching the glassplayer.png mockup:
// top-left back + title pill, top-right tracks/sources, small center
// cluster, lock bottom-left, seekbar with 85% diamond. Tap toggles,
// double-tap sides seek ±10s (with flash), auto-hides after 4s while
// playing. Lock mode shows only the unlock button and disables gestures.
import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../models.dart';
import 'glass_surface.dart';

String fmtPlayerTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

class GlassPlayerControls extends StatefulWidget {
  final Player player;
  final String title;
  final String status;
  final List<SkipInterval> skips;
  final bool showSkipButtons;
  final VoidCallback onBack;
  final VoidCallback onAudio;
  final VoidCallback onSubs;
  final VoidCallback? onSources;
  final VoidCallback? onCycleSpeed;
  final VoidCallback? onCycleFit;
  final VoidCallback? onEpisodes;      // episode list panel
  final VoidCallback? onExternal;      // open in external player
  final VoidCallback? onNextEpisode;   // jump to next episode

  const GlassPlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.status,
    required this.skips,
    required this.showSkipButtons,
    required this.onBack,
    required this.onAudio,
    required this.onSubs,
    this.onSources,
    this.onCycleSpeed,
    this.onCycleFit,
    this.onEpisodes,
    this.onExternal,
    this.onNextEpisode,
  });

  @override
  State<GlassPlayerControls> createState() => _GlassPlayerControlsState();
}

class _GlassPlayerControlsState extends State<GlassPlayerControls> {
  bool _visible = true;
  bool _dragging = false;
  bool _locked = false;
  Timer? _hideTimer;
  Timer? _flashTimer;
  StreamSubscription<bool>? _playSub;
  Offset _lastTap = Offset.zero;
  IconData? _flash;

  Player get _p => widget.player;

  @override
  void initState() {
    super.initState();
    _playSub = _p.stream.playing.listen((playing) {
      // Pausing keeps controls on screen; playing schedules the hide.
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (mounted) setState(() => _visible = true);
      }
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _playSub?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_p.state.playing || _dragging || _locked) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _show() {
    if (_locked) return;
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _seekBy(int seconds) {
    final dur = _p.state.duration;
    var t = _p.state.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    _p.seek(t);
    _scheduleHide();
  }

  void _flashIcon(IconData icon) {
    setState(() => _flash = icon);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _locked ? null : () => _visible ? setState(() => _visible = false) : _show(),
      onDoubleTapDown: _locked ? null : (d) => _lastTap = d.localPosition,
      onDoubleTap: _locked
          ? null
          : () {
              final w = context.size?.width ?? 0;
              final left = _lastTap.dx < w / 2;
              _seekBy(left ? -10 : 10);
              _flashIcon(left ? Icons.replay_10 : Icons.forward_10);
            },
      child: AnimatedOpacity(
        opacity: _visible || _locked ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !_visible && !_locked, child: _overlay()),
      ),
    );
  }

  Widget _overlay() {
    if (_locked) {
      return Stack(children: [
        Positioned(
          left: 16,
          bottom: 16,
          child: GlassButton(
            icon: Icons.lock_outline,
            circle: true,
            size: 40,
            iconSize: 20,
            onTap: () {
              setState(() => _locked = false);
              _show();
            },
          ),
        ),
      ]);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrims so white glass stays legible on bright frames.
        const Positioned(
          top: 0, left: 0, right: 0, height: 130,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: 0, left: 0, right: 0, height: 200,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _topBar(),
                Expanded(child: Center(child: _centerCluster())),
                _bottomBar(),
              ],
            ),
          ),
        ),
        // Double-tap seek feedback — always in the tree so the fade-out
        // actually animates (removing the subtree kills the animation).
        IgnorePointer(
          child: Center(
            child: AnimatedOpacity(
              opacity: _flash == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0x59000000), shape: BoxShape.circle,
                ),
                child: Icon(_flash ?? Icons.replay_10,
                    color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        GlassButton(icon: Icons.arrow_back, size: 40, iconSize: 20, circle: true, onTap: widget.onBack),
        if (widget.onEpisodes != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.view_list_outlined, size: 40, iconSize: 20, circle: true,
              onTap: widget.onEpisodes!),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: GlassSurface(
            radius: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (widget.status.isNotEmpty)
                    Text(
                      widget.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GlassButton(icon: Icons.subtitles_outlined, size: 40, iconSize: 20, circle: true, onTap: widget.onSubs),
        const SizedBox(width: 8),
        GlassButton(icon: Icons.music_note, size: 40, iconSize: 20, circle: true, onTap: widget.onAudio),
        if (widget.onSources != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.dns_outlined, size: 40, iconSize: 20, circle: true, onTap: widget.onSources!),
        ],
        if (widget.onExternal != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.open_in_new, size: 40, iconSize: 20, circle: true,
              onTap: widget.onExternal!),
        ],
        if (widget.onSources != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.dns_outlined, size: 40, iconSize: 20, circle: true, onTap: widget.onSources!),
        ],
      ],
    );
  }

  Widget _centerCluster() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassButton(icon: Icons.replay_10, size: 48, iconSize: 24, circle: true, onTap: () => _seekBy(-10)),
        const SizedBox(width: 24),
        StreamBuilder<bool>(
          stream: _p.stream.playing,
          initialData: _p.state.playing,
          builder: (_, snap) => GlassButton(
            icon: (snap.data ?? false) ? Icons.pause : Icons.play_arrow,
            size: 68, iconSize: 38, circle: true,
            onTap: () {
              _p.playOrPause();
              _scheduleHide();
            },
          ),
        ),
        const SizedBox(width: 24),
        GlassButton(icon: Icons.forward_10, size: 48, iconSize: 24, circle: true, onTap: () => _seekBy(10)),
      ],
    );
  }

  Widget _bottomBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSkipButtons && widget.skips.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in widget.skips)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GlassSurface(
                        radius: 12,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () => _p.seek(Duration(milliseconds: (s.end * 1000).toInt())),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Text(s.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Row(
          children: [
            GlassButton(
              icon: Icons.lock_open,
              size: 36, iconSize: 18, circle: true,
              onTap: () {
                setState(() => _locked = true);
                _hideTimer?.cancel();
              },
            ),
            if (widget.onCycleFit != null) ...[
              const SizedBox(width: 8),
              GlassButton(icon: Icons.aspect_ratio, size: 36, iconSize: 18,
                  circle: true, onTap: widget.onCycleFit!),
            ],
            if (widget.onCycleSpeed != null) ...[
              const SizedBox(width: 8),
              _RatePill(player: _p, onTap: widget.onCycleSpeed!),
            ],
            const SizedBox(width: 8),
            StreamBuilder<Duration>(
              stream: _p.stream.position,
              initialData: _p.state.position,
              builder: (_, posSnap) => StreamBuilder<Duration>(
                stream: _p.stream.duration,
                initialData: _p.state.duration,
                builder: (_, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  return Expanded(
                    child: Row(
                      children: [
                        Text(fmtPlayerTime(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SeekBar(
                            position: pos,
                            duration: dur,
                            onSeek: (d) => _p.seek(d),
                            onDragging: (v) {
                              _dragging = v;
                              _scheduleHide();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('-${fmtPlayerTime(dur - pos)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        if (widget.onNextEpisode != null) ...[
                          const SizedBox(width: 8),
                          GlassButton(icon: Icons.skip_next, size: 36, iconSize: 18,
                              circle: true, onTap: widget.onNextEpisode!),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  final Duration position, duration;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onDragging;
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onDragging,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag; // 0..1 while dragging

  double _ratioAt(double dx, double w) => ((dx - 8) / (w - 16)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    final live = total > 0 ? widget.position.inMilliseconds / total : 0.0;
    final ratio = (_drag ?? live).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (total > 0) {
              widget.onSeek(Duration(milliseconds: (_ratioAt(d.localPosition.dx, w) * total).toInt()));
            }
          },
          onHorizontalDragStart: (d) {
            widget.onDragging(true);
            setState(() => _drag = _ratioAt(d.localPosition.dx, w));
          },
          onHorizontalDragUpdate: (d) => setState(() => _drag = _ratioAt(d.localPosition.dx, w)),
          onHorizontalDragEnd: (_) {
            if (_drag != null && total > 0) {
              widget.onSeek(Duration(milliseconds: (_drag! * total).toInt()));
            }
            widget.onDragging(false);
            setState(() => _drag = null);
          },
          child: SizedBox(
            height: 32,
            child: CustomPaint(painter: _SeekPainter(ratio, 0.85, ratio >= 0.85)),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double ratio, marker;
  final bool passed;
  _SeekPainter(this.ratio, this.marker, this.passed);

  @override
  void paint(Canvas canvas, Size s) {
    const pad = 8.0;
    final left = pad, right = s.width - pad, y = s.height / 2;
    final trackW = right - left;
    final track = RRect.fromLTRBR(left, y - 2, right, y + 2, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = const Color(0x40FFFFFF));
    final x = left + trackW * ratio;
    canvas.drawRRect(
      RRect.fromLTRBR(left, y - 2, x, y + 2, const Radius.circular(2)),
      Paint()..color = Colors.white,
    );
    // 85% marker (diamond) — turns green once passed.
    final mx = left + trackW * marker;
    final d = Path()
      ..moveTo(mx, y - 6)
      ..lineTo(mx + 5, y)
      ..lineTo(mx, y + 6)
      ..lineTo(mx - 5, y)
      ..close();
    canvas.drawPath(d, Paint()..color = passed ? Colors.greenAccent : Colors.white70);
    // Thumb.
    canvas.drawCircle(
        Offset(x, y),
        7,
        Paint()
          ..color = Colors.black26
          ..imageFilter = ImageFilter.blur(sigmaX: 3, sigmaY: 3));
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SeekPainter o) => o.ratio != ratio || o.passed != passed;
}

/// Glass pill that shows the current playback rate (mpvKt style 1.00x).
class _RatePill extends StatelessWidget {
  final Player player;
  final VoidCallback onTap;
  const _RatePill({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.rate,
      initialData: player.state.rate,
      builder: (_, snap) {
        final r = snap.data ?? 1.0;
        return GlassSurface(
          radius: 12,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Text('${r.toStringAsFixed(2)}x',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        );
      },
    );
  }
}
