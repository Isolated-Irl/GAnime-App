// Overlay controls for the media_kit player, styled with GlassSurface.
// Compact "glass pill" layout matching the glassplayer.png mockup:
// top-left back + title pill, top-right tracks/sources, small center
// cluster, lock bottom-left, seekbar with 85% diamond. Tap toggles,
// double-tap sides seek ±10s (with flash), auto-hides after 4s while
// playing. Lock mode shows only the unlock button and disables gestures.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
  final List<double> chapters; // 0..1 ratios for seekbar breaks (mpvKt style)
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
  final bool isHw;                     // active decoder state (tappable badge)
  final VoidCallback? onToggleHw;        // toggles HW/SW decoding mid-playback

  const GlassPlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.status,
    required this.skips,
    required this.chapters,
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
    this.isHw = true,
    this.onToggleHw,
  });

  @override
  State<GlassPlayerControls> createState() => _GlassPlayerControlsState();
}

class _GlassPlayerControlsState extends State<GlassPlayerControls> {
  bool _visible = true;
  bool _dragging = false;
  bool _locked = false;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playSub;
  Offset _lastTap = Offset.zero;
  // Double-tap events go through a notifier so ONLY the tapped side's
  // button animates. No setState => the other two center buttons (and the
  // rest of the controls) are not rebuilt at all.
  final ValueNotifier<_SeekEvent> _seekEvents =
      ValueNotifier<_SeekEvent>(const _SeekEvent(0, 0));
  int _seekEventN = 0;
  // Timer display mode: 0 = remaining (-23:27), 1 = total (23:49).
  // (Elapsed is already on the left, so it's not in the cycle.)
  int _timeMode = 0;

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
    _seekEvents.dispose();
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

  // Double-tap feedback: only when the controls are open, and only the
  // button on the tapped side animates (rewind = left, forward = right).
  // When the controls are hidden the seek happens silently.
  void _pulseSeekButton(bool left) {
    if (!_visible) return;
    _seekEvents.value = _SeekEvent(left ? -1 : 1, ++_seekEventN);
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
              _pulseSeekButton(left);
            },
      child: AnimatedOpacity(
        opacity: _visible || _locked ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !_visible && !_locked, child: _overlay()),
      ),
    );
  }

  double _sideMargin(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return math.max(pad.left, pad.right) + 16;
  }

  Widget _overlay() {
    if (_locked) {
      return Stack(children: [
        Positioned(
          left: _sideMargin(context),
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
        // Same margin on BOTH sides: the larger of the left/right system
        // insets (camera cutout) is used for each side, so the controls sit
        // evenly instead of the right side hugging the edge.
        Builder(builder: (context) {
          final pad = MediaQuery.paddingOf(context);
          final side = _sideMargin(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(side, pad.top + 8, side, pad.bottom + 8),
            child: Column(
              children: [
                _topBar(),
                // True visual center: offset down to compensate for the
                // taller top bar pushing the cluster optically high.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(child: _centerCluster()),
                  ),
                ),
                _bottomBar(),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        GlassButton(icon: Icons.arrow_back, size: 40, iconSize: 20, circle: true, onTap: widget.onBack),
        const SizedBox(width: 10),
        // Fixed pill: always fills the space between the back button and
        // the right-hand buttons, so it never grows or shrinks with the
        // title. Long titles scroll (marquee) instead of being cut off.
        Expanded(
          child: GlassSurface(
            radius: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MarqueeText(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (widget.status.isNotEmpty)
                    _MarqueeText(
                      widget.status,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // RIGHT — fixed order: external, HW badge, audio, subs, stream, episode.
        if (widget.onExternal != null) ...[
          GlassButton(icon: Icons.open_in_new, size: 40, iconSize: 20, circle: true,
              onTap: widget.onExternal!),
          const SizedBox(width: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: widget.onToggleHw,
            child: GlassSurface(
              radius: 12,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Text(
                  widget.isHw ? 'HW' : 'SW',
                  style: TextStyle(
                    color: widget.isHw
                        ? const Color(0xFF22C55E)
                        : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        GlassButton(icon: Icons.music_note, size: 40, iconSize: 20, circle: true, onTap: widget.onAudio),
        const SizedBox(width: 8),
        GlassButton(icon: Icons.subtitles_outlined, size: 40, iconSize: 20, circle: true, onTap: widget.onSubs),
        if (widget.onSources != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.dns_outlined, size: 40, iconSize: 20, circle: true, onTap: widget.onSources!),
        ],
        if (widget.onEpisodes != null) ...[
          const SizedBox(width: 8),
          GlassButton(icon: Icons.view_list_outlined, size: 40, iconSize: 20, circle: true,
              onTap: widget.onEpisodes!),
        ],
      ],
    );
  }

  Widget _centerCluster() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SeekPulseButton(
          side: -1,
          events: _seekEvents,
          icon: Icons.replay_10,
          onTap: () => _seekBy(-10),
        ),
        const SizedBox(width: 24),
        // Play/pause button with an in-button buffering spinner:
        // while buffering, a 12-spoke style spinner replaces the icon
        // (the button stays tappable); the old full-screen centered
        // spinner is gone so nothing clips under the controls.
        StreamBuilder<bool>(
          stream: _p.stream.buffering,
          initialData: _p.state.buffering,
          builder: (_, bufSnap) {
            final buffering = bufSnap.data ?? false;
            return StreamBuilder<bool>(
              stream: _p.stream.playing,
              initialData: _p.state.playing,
              builder: (_, playSnap) {
                final playing = playSnap.data ?? false;
                return GlassSurface(
                  radius: 34,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () {
                        _p.playOrPause();
                        _scheduleHide();
                      },
                      customBorder: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(34)),
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: Center(
                          child: buffering
                              ? const SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 38,
                                  shadows: const [
                                    Shadow(color: Color(0x66000000), blurRadius: 4),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(width: 24),
        _SeekPulseButton(
          side: 1,
          events: _seekEvents,
          icon: Icons.forward_10,
          onTap: () => _seekBy(10),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Skip buttons are time-gated: each appears only while playback is
        // inside its window (5s lead-in so it's there when the OP starts)
        // and disappears once the window passes — mpvKt behavior.
        if (widget.showSkipButtons && widget.skips.isNotEmpty)
          StreamBuilder<Duration>(
            stream: _p.stream.position,
            initialData: _p.state.position,
            builder: (_, snap) {
              final pos = (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
              final active = widget.skips
                  .where((s) => pos >= s.start - 5 && pos < s.end)
                  .toList();
              if (active.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in active)
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
              );
            },
          ),
        // Keys row (mpv.kt style): left cluster lock/aspect/speed,
        // right cluster next-episode.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
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
              ],
            ),
            if (widget.onNextEpisode != null)
              GlassButton(icon: Icons.skip_next, size: 36, iconSize: 18,
                  circle: true, onTap: widget.onNextEpisode!),
          ],
        ),
        const SizedBox(height: 6),
        // Full-width seekbar on its own row, flanked by time labels.
        StreamBuilder<Duration>(
          stream: _p.stream.position,
          initialData: _p.state.position,
          builder: (_, posSnap) => StreamBuilder<Duration>(
            stream: _p.stream.duration,
            initialData: _p.state.duration,
            builder: (_, durSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur = durSnap.data ?? Duration.zero;
              // Right timer cycles on tap: remaining → total (VLC-style).
              // Elapsed is already shown on the left, so it's skipped.
              final rightLabel = switch (_timeMode) {
                1 => fmtPlayerTime(dur),
                _ => '-${fmtPlayerTime(dur - pos)}',
              };
              return Row(
                children: [
                  // Fixed width so the seekbar doesn't shift as digits change.
                  SizedBox(
                    width: 52,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(fmtPlayerTime(pos),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SeekBar(
                      position: pos,
                      duration: dur,
                      skips: widget.skips,
                      chapters: widget.chapters,
                      onSeek: (d) => _p.seek(d),
                      onDragging: (v) {
                        _dragging = v;
                        _scheduleHide();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _timeMode = (_timeMode + 1) % 2);
                      _scheduleHide();
                    },
                    child: SizedBox(
                      width: 60,
                      height: 32,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(rightLabel,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  final Duration position, duration;
  final List<SkipInterval> skips;
  final List<double> chapters; // 0..1 — drawn as breaks (mpvKt style)
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onDragging;
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.skips,
    required this.chapters,
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
            child: CustomPaint(
              painter: _SeekPainter(
                ratio,
                0.85,
                ratio >= 0.85,
                // Chapter breaks from mpv chapter-list (mpvKt style).
                // Falls back to skip-window starts if no chapters.
                widget.chapters.isNotEmpty
                    ? widget.chapters
                    : (total > 0
                        ? [
                            for (final s in widget.skips)
                              if (s.end * 1000 <= total)
                                (s.start * 1000 / total).clamp(0.0, 1.0),
                          ]
                        : const <double>[]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double ratio, marker;
  final bool passed;
  final List<double> markers; // chapter positions 0..1 — drawn as breaks
  _SeekPainter(this.ratio, this.marker, this.passed,
      [this.markers = const <double>[]]);

  @override
  void paint(Canvas canvas, Size s) {
    const pad = 8.0;
    final left = pad, right = s.width - pad, y = s.height / 2;
    final trackW = right - left;
    const breakW = 3.0; // gap width at each chapter (mpvKt style)

    // Build sorted break positions in pixels.
    final breaks = markers
        .map((m) => left + trackW * m.clamp(0.0, 1.0))
        .where((bx) => bx > left + 4 && bx < right - 4)
        .toList()
      ..sort();

    // Draw track + progress as segments, leaving gaps at breaks.
    final trackPaint = Paint()..color = const Color(0x40FFFFFF);
    final progressPaint = Paint()..color = Colors.white;
    final x = left + trackW * ratio;

    double segStart = left;
    for (final bx in [...breaks, right + 10]) {
      final segEnd = (bx - breakW / 2).clamp(segStart, right);
      if (segEnd > segStart) {
        // Background track segment.
        canvas.drawRRect(
          RRect.fromLTRBR(segStart, y - 3, segEnd, y + 3, const Radius.circular(3)),
          trackPaint,
        );
        // Progress segment (only up to current position).
        final pxEnd = segEnd.clamp(segStart, x);
        if (pxEnd > segStart) {
          canvas.drawRRect(
            RRect.fromLTRBR(segStart, y - 3, pxEnd, y + 3, const Radius.circular(3)),
            progressPaint,
          );
        }
      }
      segStart = bx + breakW / 2;
      if (segStart >= right) break;
    }

    // 85% marker (diamond) — turns green once passed.
    final mx = left + trackW * marker;
    final d = Path()
      ..moveTo(mx, y - 6)
      ..lineTo(mx + 5, y)
      ..lineTo(mx, y + 6)
      ..lineTo(mx - 5, y)
      ..close();
    canvas.drawPath(d, Paint()..color = passed ? Colors.greenAccent : Colors.white70);
    // Thumb: two flat circles instead of a blurred shadow — this painter
    // repaints on every position tick, so a per-tick blur was wasted GPU.
    canvas.drawCircle(Offset(x, y + 1.5), 7.5, Paint()..color = Colors.black26);
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SeekPainter o) =>
      o.ratio != ratio ||
      o.passed != passed ||
      o.marker != marker ||
      o.markers.length != markers.length;
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


/// One double-tap event: [side] -1 = rewind, 1 = forward; [n] makes every
/// tap a distinct value so repeated taps on the same side re-trigger.
class _SeekEvent {
  final int side, n;
  const _SeekEvent(this.side, this.n);
}

/// A seek button with its OWN animation controller. It only reacts to
/// events for its side, and only its transform changes — the glass child is
/// built once and never rebuilt, so the other buttons stay perfectly still.
class _SeekPulseButton extends StatefulWidget {
  final int side;
  final ValueListenable<_SeekEvent> events;
  final IconData icon;
  final VoidCallback onTap;
  const _SeekPulseButton({
    required this.side,
    required this.events,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_SeekPulseButton> createState() => _SeekPulseButtonState();
}

class _SeekPulseButtonState extends State<_SeekPulseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Widget _button = GlassButton(
    icon: widget.icon,
    size: 48,
    iconSize: 24,
    circle: true,
    onTap: widget.onTap,
  );

  @override
  void initState() {
    super.initState();
    widget.events.addListener(_onEvent);
  }

  void _onEvent() {
    if (widget.events.value.side == widget.side) _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.events.removeListener(_onEvent);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: _button,
      builder: (_, child) {
        // 0 -> 1 -> 0 bump: half turn out and back, with a small scale pop.
        final bump = math.sin(math.pi * Curves.easeInOut.transform(_c.value));
        return Transform.scale(
          scale: 1 + 0.14 * bump,
          child: Transform.rotate(angle: widget.side * math.pi * bump, child: child),
        );
      },
    );
  }
}

/// Single-line text that scrolls sideways (with pauses) only when it does
/// not fit; short text just sits still.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText(this.text, {required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _sc = ScrollController();
  int _gen = 0; // bumps whenever the text changes -> restarts the loop
  int _startedFor = -1;

  @override
  void didUpdateWidget(covariant _MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _gen++;
      if (_sc.hasClients) _sc.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _gen++; // stops the loop
    _sc.dispose();
    super.dispose();
  }

  Future<void> _loop(int gen) async {
    Future<bool> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      return mounted && gen == _gen && _sc.hasClients;
    }

    if (!await wait(1500)) return;
    while (mounted && gen == _gen && _sc.hasClients) {
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) return;
      await _sc.animateTo(
        max,
        duration: Duration(milliseconds: (max / 40 * 1000).round()), // 40 px/s
        curve: Curves.linear,
      );
      if (!await wait(1200)) return;
      _sc.jumpTo(0);
      if (!await wait(1500)) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final overflows = tp.width > c.maxWidth;
      tp.dispose();
      if (!overflows) {
        _startedFor = -1;
        return Text(widget.text,
            maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: widget.style);
      }
      if (_startedFor != _gen) {
        _startedFor = _gen;
        final g = _gen;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && g == _gen) _loop(g);
        });
      }
      return SingleChildScrollView(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
      );
    });
  }
}
