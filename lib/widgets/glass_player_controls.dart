import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/aniskip.dart';
import 'glass_surface.dart';

String _fmt(Duration d) {
  final totalSecs = d.inSeconds.abs();
  final h = totalSecs ~/ 3600;
  final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (totalSecs % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class GlassPlayerControls extends StatefulWidget {
  final Player player;
  final bool isHw;
  final VoidCallback onToggleHw;
  final String title;
  final String status;
  final List<SkipInterval> skips;
  final List<double> chapters;
  final bool showSkipButtons;
  final int seekInterval;
  final bool swipeToSeek;
  final VoidCallback onBack;
  final VoidCallback onAudio;
  final VoidCallback onSubs;
  final VoidCallback onCycleSpeed;
  final VoidCallback onCycleFit;
  final VoidCallback? onSources;
  final VoidCallback? onEpisodes;
  final VoidCallback onExternal;
  final VoidCallback? onNextEpisode;

  const GlassPlayerControls({
    super.key,
    required this.player,
    required this.isHw,
    required this.onToggleHw,
    required this.title,
    required this.status,
    required this.skips,
    this.chapters = const [],
    required this.showSkipButtons,
    this.seekInterval = 10,
    this.swipeToSeek = true,
    required this.onBack,
    required this.onAudio,
    required this.onSubs,
    required this.onCycleSpeed,
    required this.onCycleFit,
    this.onSources,
    this.onEpisodes,
    required this.onExternal,
    this.onNextEpisode,
  });

  @override
  State<GlassPlayerControls> createState() => _GlassPlayerControlsState();
}

class _GlassPlayerControlsState extends State<GlassPlayerControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _topSlide;
  late final Animation<Offset> _bottomSlide;
  late final Animation<double> _centerScale;

  bool _visible = true;
  bool _locked = false;
  Timer? _hideTimer;

  // Double-tap seek flash state
  int _doubleTapAccumSecs = 0;
  bool? _doubleTapRight;
  Timer? _doubleTapTimer;

  // Horizontal swipe-to-seek state
  bool _isHorizontalSwiping = false;
  Duration _swipeStartPos = Duration.zero;
  Duration _swipeTargetPos = Duration.zero;
  double _swipeDeltaX = 0;

  // Vertical swipe (left = brightness, right = volume) state
  bool _isVerticalSwiping = false;
  bool _verticalIsVolume = true;
  double _brightness = 1.0; // 0.15 .. 1.0 visual brightness
  double _hudValue = 1.0;   // 0.0 .. 1.0 shown in HUD
  Timer? _hudTimer;
  bool _showVerticalHud = false;

  // Long-press 2x speed state
  bool _isLongPress2x = false;
  double _savedRateBefore2x = 1.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 170),
      value: 1.0,
    );
    _fade = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _topSlide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(_fade);
    _bottomSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(_fade);
    _centerScale = Tween<double>(begin: 0.92, end: 1.0).animate(_fade);

    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _doubleTapTimer?.cancel();
    _hudTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_visible) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.player.state.playing && !_isHorizontalSwiping) {
        _setVisible(false);
      }
    });
  }

  void _setVisible(bool v) {
    _hideTimer?.cancel();
    if (_visible == v) {
      if (v) _scheduleHide();
      return;
    }
    setState(() => _visible = v);
    if (v) {
      _anim.forward();
      _scheduleHide();
    } else {
      _anim.reverse();
    }
  }

  void _toggleVisible() => _setVisible(!_visible);

  void _seekRelative(int deltaSeconds) {
    final dur = widget.player.state.duration;
    final pos = widget.player.state.position;
    final nextMs = (pos.inMilliseconds + deltaSeconds * 1000)
        .clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 86400000);
    widget.player.seek(Duration(milliseconds: nextMs));
    if (_visible) _scheduleHide();
  }

  void _handleDoubleTap(TapDownDetails details, double width) {
    if (_locked) return;
    final rightSide = details.localPosition.dx > width / 2;
    final step = rightSide ? widget.seekInterval : -widget.seekInterval;
    _seekRelative(step);

    _doubleTapTimer?.cancel();
    setState(() {
      if (_doubleTapRight == rightSide) {
        _doubleTapAccumSecs += step;
      } else {
        _doubleTapRight = rightSide;
        _doubleTapAccumSecs = step;
      }
    });
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _doubleTapRight = null;
          _doubleTapAccumSecs = 0;
        });
      }
    });
  }

  // ---- Long-press 2x speed ----
  void _onLongPressStart(LongPressStartDetails _) {
    if (_locked) return;
    _savedRateBefore2x = widget.player.state.rate;
    widget.player.setRate(2.0);
    setState(() => _isLongPress2x = true);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_isLongPress2x) return;
    widget.player.setRate(_savedRateBefore2x);
    setState(() => _isLongPress2x = false);
  }

  // ---- Horizontal swipe to seek ----
  void _onHorizontalDragStart(DragStartDetails d) {
    if (_locked || !widget.swipeToSeek) return;
    final dur = widget.player.state.duration;
    if (dur.inMilliseconds <= 0) return;
    _isHorizontalSwiping = true;
    _swipeStartPos = widget.player.state.position;
    _swipeTargetPos = _swipeStartPos;
    _swipeDeltaX = 0;
    setState(() {});
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, double width) {
    if (!_isHorizontalSwiping) return;
    final dur = widget.player.state.duration;
    if (dur.inMilliseconds <= 0 || width <= 0) return;
    _swipeDeltaX += d.primaryDelta ?? 0;
    // Full screen width swipe = ±120 seconds (scaled smoothly)
    final deltaMs = ((_swipeDeltaX / width) * 120000).round();
    final targetMs =
        (_swipeStartPos.inMilliseconds + deltaMs).clamp(0, dur.inMilliseconds);
    setState(() => _swipeTargetPos = Duration(milliseconds: targetMs));
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (!_isHorizontalSwiping) return;
    final target = _swipeTargetPos;
    setState(() => _isHorizontalSwiping = false);
    widget.player.seek(target);
  }

  // ---- Vertical swipe: left = brightness, right = volume ----
  void _onVerticalDragStart(DragStartDetails d, double width) {
    if (_locked) return;
    _isVerticalSwiping = true;
    _verticalIsVolume = d.localPosition.dx >= width / 2;
    _hudTimer?.cancel();
    if (_verticalIsVolume) {
      _hudValue = (widget.player.state.volume / 100.0).clamp(0.0, 1.0);
    } else {
      _hudValue = _brightness;
    }
    setState(() => _showVerticalHud = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails d, double height) {
    if (!_isVerticalSwiping || height <= 0) return;
    final delta = -(d.primaryDelta ?? 0) / (height * 0.75);
    if (_verticalIsVolume) {
      _hudValue = (_hudValue + delta).clamp(0.0, 1.0);
      widget.player.setVolume(_hudValue * 100.0);
    } else {
      _brightness = (_brightness + delta).clamp(0.05, 1.0);
      _hudValue = _brightness;
    }
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    if (!_isVerticalSwiping) return;
    _isVerticalSwiping = false;
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showVerticalHud = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final dimAlpha = ((1.0 - _brightness) * 0.82).clamp(0.0, 0.82);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Visual brightness overlay (zero native plugin dependency)
            if (dimAlpha > 0.005)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: dimAlpha),
                ),
              ),

            // Full-screen gesture layer
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleVisible,
              onDoubleTapDown: (d) => _handleDoubleTap(d, w),
              onDoubleTap: () {},
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onHorizontalDragStart:
                  widget.swipeToSeek ? _onHorizontalDragStart : null,
              onHorizontalDragUpdate: widget.swipeToSeek
                  ? (d) => _onHorizontalDragUpdate(d, w)
                  : null,
              onHorizontalDragEnd:
                  widget.swipeToSeek ? _onHorizontalDragEnd : null,
              onVerticalDragStart: (d) => _onVerticalDragStart(d, w),
              onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, h),
              onVerticalDragEnd: _onVerticalDragEnd,
              child: const SizedBox.expand(),
            ),

            // Buffering indicator
            IgnorePointer(
              child: Center(
                child: StreamBuilder<bool>(
                  stream: widget.player.stream.buffering,
                  initialData: widget.player.state.buffering,
                  builder: (_, snap) {
                    if (snap.data != true) return const SizedBox.shrink();
                    return const SizedBox(
                      width: 46,
                      height: 46,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Double-tap seek feedback pill
            if (_doubleTapRight != null)
              IgnorePointer(
                child: Align(
                  alignment: _doubleTapRight!
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: GlassSurface(
                      radius: 999,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _doubleTapRight!
                                  ? Icons.fast_forward_rounded
                                  : Icons.fast_rewind_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_doubleTapAccumSecs > 0 ? '+' : ''}${_doubleTapAccumSecs}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Swipe-to-seek center time preview
            if (_isHorizontalSwiping)
              IgnorePointer(
                child: Center(
                  child: GlassSurface(
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Builder(builder: (_) {
                        final diffSecs = (_swipeTargetPos - _swipeStartPos)
                            .inSeconds;
                        final sign = diffSecs >= 0 ? '+' : '-';
                        return Text(
                          '${_fmt(_swipeTargetPos)}  ($sign${_fmt(Duration(seconds: diffSecs.abs()))})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),

            // Vertical Brightness / Volume HUD pill
            if (_showVerticalHud)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: GlassSurface(
                      radius: 999,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _verticalIsVolume
                                  ? (_hudValue <= 0.01
                                      ? Icons.volume_off_rounded
                                      : _hudValue < 0.5
                                          ? Icons.volume_down_rounded
                                          : Icons.volume_up_rounded)
                                  : Icons.brightness_6_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 110,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _hudValue.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 38,
                              child: Text(
                                '${(_hudValue * 100).round()}%',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Long-press 2x speed pill
            if (_isLongPress2x)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: GlassSurface(
                      radius: 999,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                color: Colors.amberAccent, size: 18),
                            SizedBox(width: 4),
                            Text(
                              '2.0x Speed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            //AniSkip floating button (visible even when controls are hidden)
            if (widget.showSkipButtons && widget.skips.isNotEmpty && !_locked)
              _ActiveSkipButton(
                player: widget.player,
                skips: widget.skips,
              ),

            // Animated Controls Overlay (RepaintBoundary prevents re-blurring jank)
            IgnorePointer(
              ignoring: !_visible,
              child: FadeTransition(
                opacity: _fade,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x99000000),
                        Color(0x22000000),
                        Color(0x22000000),
                        Color(0xB3000000),
                      ],
                      stops: [0.0, 0.25, 0.72, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: _locked
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: _TapScaleButton(
                                onTap: () {
                                  setState(() => _locked = false);
                                  _scheduleHide();
                                },
                                child: GlassSurface(
                                  radius: 999,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_rounded,
                                            color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Text('Tap to Unlock',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              // Top bar
                              Align(
                                alignment: Alignment.topCenter,
                                child: SlideTransition(
                                  position: _topSlide,
                                  child: RepaintBoundary(
                                    child: _buildTopBar(),
                                  ),
                                ),
                              ),

                              // Center transport controls
                              Center(
                                child: ScaleTransition(
                                  scale: _centerScale,
                                  child: RepaintBoundary(
                                    child: _buildCenterControls(),
                                  ),
                                ),
                              ),

                              // Bottom seekbar + action pills
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: SlideTransition(
                                  position: _bottomSlide,
                                  child: RepaintBoundary(
                                    child: _buildBottomBar(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _TapScaleButton(
            onTap: widget.onBack,
            child: GlassSurface(
              radius: 999,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.status.isNotEmpty)
                  Text(
                    widget.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TapScaleButton(
            onTap: () {
              widget.onToggleHw();
              _scheduleHide();
            },
            child: GlassSurface(
              radius: 999,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  widget.isHw ? 'HW' : 'SW',
                  style: TextStyle(
                    color: widget.isHw ? const Color(0xFF4ADE80) : Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _topIconBtn(Icons.audiotrack_rounded, 'Audio tracks', widget.onAudio),
          const SizedBox(width: 8),
          _topIconBtn(Icons.subtitles_rounded, 'Subtitles', widget.onSubs),
          const SizedBox(width: 8),
          _topIconBtn(Icons.open_in_new_rounded, 'External player',
              widget.onExternal),
        ],
      ),
    );
  }

  Widget _topIconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return _TapScaleButton(
      onTap: () {
        _scheduleHide();
        onTap();
      },
      child: GlassSurface(
        radius: 999,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TapScaleButton(
          onTap: () => _seekRelative(-widget.seekInterval),
          child: GlassSurface(
            radius: 999,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.replay_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.seekInterval}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        StreamBuilder<bool>(
          stream: widget.player.stream.playing,
          initialData: widget.player.state.playing,
          builder: (_, snap) {
            final playing = snap.data ?? false;
            return _TapScaleButton(
              onTap: () {
                widget.player.playOrPause();
                _scheduleHide();
              },
              child: GlassSurface(
                radius: 999,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey<bool>(playing),
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 24),
        _TapScaleButton(
          onTap: () => _seekRelative(widget.seekInterval),
          child: GlassSurface(
            radius: 999,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.seekInterval}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.forward_rounded,
                      color: Colors.white, size: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeekbarSection(
            player: widget.player,
            chapters: widget.chapters,
            onInteraction: _scheduleHide,
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _bottomPill(
                  icon: Icons.lock_open_rounded,
                  label: 'Lock',
                  onTap: () => setState(() => _locked = true),
                ),
                const SizedBox(width: 8),
                StreamBuilder<double>(
                  stream: widget.player.stream.rate,
                  initialData: widget.player.state.rate,
                  builder: (_, snap) {
                    final r = snap.data ?? 1.0;
                    return _bottomPill(
                      icon: Icons.speed_rounded,
                      label: '${r}x',
                      onTap: () {
                        widget.onCycleSpeed();
                        _scheduleHide();
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                _bottomPill(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Fit',
                  onTap: () {
                    widget.onCycleFit();
                    _scheduleHide();
                  },
                ),
                if (widget.onSources != null) ...[
                  const SizedBox(width: 8),
                  _bottomPill(
                    icon: Icons.dns_rounded,
                    label: 'Sources',
                    onTap: () {
                      _scheduleHide();
                      widget.onSources!();
                    },
                  ),
                ],
                if (widget.onEpisodes != null) ...[
                  const SizedBox(width: 8),
                  _bottomPill(
                    icon: Icons.video_library_rounded,
                    label: 'Episodes',
                    onTap: () {
                      _scheduleHide();
                      widget.onEpisodes!();
                    },
                  ),
                ],
                if (widget.onNextEpisode != null) ...[
                  const SizedBox(width: 8),
                  _bottomPill(
                    icon: Icons.skip_next_rounded,
                    label: 'Next Ep',
                    onTap: () {
                      _scheduleHide();
                      widget.onNextEpisode!();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return _TapScaleButton(
      onTap: onTap,
      child: GlassSurface(
        radius: 999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isolated seekbar widget so high-frequency position ticks never rebuild
/// the glass buttons or interrupt open/close animations.
class _SeekbarSection extends StatefulWidget {
  final Player player;
  final List<double> chapters;
  final VoidCallback onInteraction;

  const _SeekbarSection({
    required this.player,
    required this.chapters,
    required this.onInteraction,
  });

  @override
  State<_SeekbarSection> createState() => _SeekbarSectionState();
}

class _SeekbarSectionState extends State<_SeekbarSection> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final dur = widget.player.state.duration;
        final maxMs =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final curMs =
            (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
        final shownPos = Duration(milliseconds: curMs.round());

        return Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _fmt(shownPos),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: curMs,
                      min: 0.0,
                      max: maxMs,
                      onChangeStart: (v) {
                        widget.onInteraction();
                        setState(() => _dragMs = v);
                      },
                      onChanged: (v) {
                        widget.onInteraction();
                        setState(() => _dragMs = v);
                      },
                      onChangeEnd: (v) {
                        widget.onInteraction();
                        setState(() => _dragMs = null);
                        widget.player.seek(Duration(milliseconds: v.round()));
                      },
                    ),
                  ),
                  if (widget.chapters.isNotEmpty)
                    IgnorePointer(
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final trackW = (c.maxWidth - 28).clamp(0.0, c.maxWidth);
                          return SizedBox(
                            width: trackW,
                            height: 6,
                            child: Stack(
                              children: [
                                for (final ratio in widget.chapters)
                                  Positioned(
                                    left: (ratio.clamp(0.0, 1.0) * trackW) - 1,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 2,
                                      color: Colors.black87,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                _fmt(dur),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Floating AniSkip button that only rebuilds when entering/leaving a skip interval.
class _ActiveSkipButton extends StatelessWidget {
  final Player player;
  final List<SkipInterval> skips;

  const _ActiveSkipButton({
    required this.player,
    required this.skips,
  });

  String _labelFor(String kind) {
    switch (kind.toLowerCase()) {
      case 'op':
      case 'mixed-op':
        return 'Skip Opening';
      case 'ed':
      case 'mixed-ed':
        return 'Skip Ending';
      case 'recap':
        return 'Skip Recap';
      default:
        return 'Skip ${kind.toUpperCase()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (_, snap) {
        final t = (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
        SkipInterval? active;
        for (final s in skips) {
          if (t >= s.start && t < s.end - 0.5) {
            active = s;
            break;
          }
        }
        if (active == null) return const SizedBox.shrink();
        final targetMs = (active.end * 1000).round();
        return Positioned(
          right: 20,
          bottom: 88,
          child: _TapScaleButton(
            onTap: () => player.seek(Duration(milliseconds: targetMs)),
            child: GlassSurface(
              radius: 999,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fast_forward_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _labelFor(active.kind),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tactile press-scale wrapper so every player button feels responsive.
class _TapScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapScaleButton({
    required this.child,
    required this.onTap,
  });

  @override
  State<_TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<_TapScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 95),
    reverseDuration: const Duration(milliseconds: 130),
    lowerBound: 0.91,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _ctrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _ctrl,
        child: widget.child,
      ),
    );
  }
}