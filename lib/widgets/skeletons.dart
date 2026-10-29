import 'package:flutter/material.dart';
import '../theme.dart';
import 'anime_card.dart';

/// Skeleton loading placeholders in the website's visual language: dark
/// translucent rounded shapes with a sweeping shimmer, replacing the old
/// circular spinners. Placeholders only — never fake data.
///
/// Hand-rolled (no shimmer package): a ShaderMask whose linear gradient is
/// translated by a repeating AnimationController, exactly like the classic
/// shimmer effect.

/// Gradient transform that slides the shimmer band across the child.
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

/// Wraps skeleton blocks so one shimmer band sweeps across the whole group.
class Skeleton extends StatefulWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  static const _base = Color(0xFF2A2A2A);
  static const _highlight = Color(0xFF3D3D3D);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              colors: const [_base, _highlight, _base],
              stops: const [0.0, 0.5, 1.0],
              begin: const Alignment(-1.0, 0.0),
              end: const Alignment(1.0, 0.0),
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value * 2.0 - 0.5,
              ),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// One rounded skeleton block. Painted the shimmer base colour; the
/// surrounding [Skeleton] supplies the moving highlight.
class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBlock(
      {super.key, this.width, this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Poster card skeleton (Home rails, Search/Library grids).
/// Width is unconstrained for grid use; pass a fixed width for rails.
/// Mirrors AnimeCard exactly: fixed 2:3 image (website parity), radius-10,
/// 4px gap, 13px title line, 11px score line.
Widget skeletonPosterCard({double? width}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SkeletonBlock(
          width: width, height: (width ?? 120) / kPosterArtRatio, radius: 10),
      const SizedBox(height: 4),
      const SkeletonBlock(height: 15, radius: 6),
      const SizedBox(height: 4),
      const SkeletonBlock(width: 72, height: 12, radius: 6),
    ],
  );
}

/// Home rail skeleton: title row + horizontal poster placeholders.
/// Mirrors _rail exactly: NO horizontal padding, title row ~40px tall
/// (13px uppercase title + M3 TextButton 'View All'), list directly under
/// the title with no gap, 120px posters with fixed 2:3 art + reserved
/// text block, 20px below.
Widget skeletonRail({required String title, int count = 6}) {
  return Skeleton(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBlock(
                  width: title.length * 9.5 + 8, height: 17, radius: 8),
              const SkeletonBlock(width: 80, height: 40, radius: 20),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120 / kPosterArtRatio + kPosterTextReserve,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, _) =>
                SizedBox(width: 120, child: skeletonPosterCard(width: 120)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

/// Hero banner skeleton (Home initial load): ghost of the real hero card —
/// 480px tall, radius 20 with the #333333 border, banner art, the bottom-30
/// text block (2-line 26px title, genre pills, badge pills, the two pill
/// buttons) and the dot row OVERLAID at bottom:10 inside the card.
Widget skeletonHero() {
  return Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 480,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: const Stack(
              children: [
                // Banner art.
                Positioned.fill(child: SkeletonBlock(radius: 0)),
                // Text block: left 16, right 16, bottom 30.
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 30,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2-line 26px title.
                      SkeletonBlock(height: 60, radius: 10),
                      SizedBox(height: 10),
                      // Genre pills (white12, radius 999, 11px text).
                      Row(
                        children: [
                          SkeletonBlock(width: 64, height: 22, radius: 11),
                          SizedBox(width: 6),
                          SkeletonBlock(width: 72, height: 22, radius: 11),
                          SizedBox(width: 6),
                          SkeletonBlock(width: 58, height: 22, radius: 11),
                        ],
                      ),
                      SizedBox(height: 10),
                      // Badge pills ("★ 8.4 · FORMAT · STATUS · YEAR").
                      Row(
                        children: [
                          SkeletonBlock(width: 56, height: 20, radius: 10),
                          SizedBox(width: 6),
                          SkeletonBlock(width: 44, height: 20, radius: 10),
                          SizedBox(width: 6),
                          SkeletonBlock(width: 76, height: 20, radius: 10),
                          SizedBox(width: 6),
                          SkeletonBlock(width: 52, height: 20, radius: 10),
                        ],
                      ),
                      SizedBox(height: 14),
                      // Details / + My List pill buttons.
                      Row(
                        children: [
                          Expanded(
                              child:
                                  SkeletonBlock(height: 48, radius: 24)),
                          SizedBox(width: 10),
                          Expanded(
                              child:
                                  SkeletonBlock(height: 48, radius: 24)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Dot indicators, centred, bottom 10 — inside the card.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SkeletonBlock(width: 8, height: 8, radius: 4),
                      SizedBox(width: 7),
                      SkeletonBlock(width: 6, height: 6, radius: 3),
                      SizedBox(width: 7),
                      SkeletonBlock(width: 6, height: 6, radius: 3),
                      SizedBox(width: 7),
                      SkeletonBlock(width: 6, height: 6, radius: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Poster grid skeleton (Search results loading): 3-column grid like
/// AnimeGrid, using the same fixed 2:3 art + reserved text block so the
/// ghost matches the real cards exactly on any screen width.
Widget skeletonPosterGrid({int count = 9}) {
  return Skeleton(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // NOTE: local is `columns`, not `count` — the `count` parameter
        // above is the number of skeleton cells (default 9 = 3 rows).
        // A previous `const count = 3` shadowed the parameter, so
        // itemCount silently became 3 and the grid showed a single row
        // followed by dead space.
        const columns = 3;
        const spacing = 8.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: posterGridChildAspectRatio(cellWidth),
            crossAxisSpacing: spacing,
            mainAxisSpacing: 8,
          ),
          itemCount: count,
          itemBuilder: (_, _) => skeletonPosterCard(width: cellWidth),
        );
      },
    ),
  );
}

/// Detailed episode card skeletons (Details > Episodes, 'detailed' layout):
/// horizontal strip of 84vw x 172px stills, radius 14, mirroring the real
/// `.ep-big` cards: 28px save/eye circles top corners, and the body
/// overlaid at the bottom (padding 14/14/12): S1E chip, 2-line title,
/// 2-line synopsis, runtime-left / airdate-right footer row.
Widget skeletonEpisodeDetailed({int count = 3}) {
  return Skeleton(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Same formula as the real card: 0.84 x full screen width
        // (MediaQuery, not the available width — the strip's cards
        // overflow its inset, like the website's .ep-big-strip).
        final w = MediaQuery.of(context).size.width * 0.84;
        return SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) => Container(
              width: w,
              height: 172,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFF333333)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: const Stack(
                  children: [
                    Positioned.fill(child: SkeletonBlock(radius: 0)),
                    // Save (top-left) and watched (top-right) circles.
                    Positioned(
                      top: 10,
                      left: 10,
                      child: SkeletonBlock(
                          width: 28, height: 28, radius: 14),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: SkeletonBlock(
                          width: 28, height: 28, radius: 14),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // S1E chip (padding 8x2, radius 6).
                          SkeletonBlock(
                              width: 52, height: 20, radius: 6),
                          SizedBox(height: 6),
                          // 2-line 15.5px title.
                          SkeletonBlock(height: 40, radius: 6),
                          SizedBox(height: 4),
                          // 2-line 12.5px synopsis.
                          SkeletonBlock(height: 36, radius: 6),
                          SizedBox(height: 8),
                          // Footer: runtime left, airdate right.
                          Row(
                            children: [
                              SkeletonBlock(
                                  width: 60, height: 14, radius: 7),
                              Spacer(),
                              SkeletonBlock(
                                  width: 90, height: 14, radius: 7),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Minimum episode card skeletons (Details > Episodes, 'minimum' layout):
/// full-width 16:9 picture cards, radius 12, mirroring the website's
/// `.ep-pic`: 28px save/eye circles top corners, white-bordered "EP n"
/// badge bottom-left, date badge bottom-right. No title text.
Widget skeletonEpisodeMinimum({int count = 3}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF333333)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(11)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: SkeletonBlock(radius: 0)),
                      // Save (top-left) and watched (top-right) circles.
                      Positioned(
                        top: 10,
                        left: 10,
                        child: SkeletonBlock(
                            width: 28, height: 28, radius: 14),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: SkeletonBlock(
                            width: 28, height: 28, radius: 14),
                      ),
                      // White-bordered EP pill, bottom-left.
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          width: 72,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            border: Border.all(
                                color: Colors.white, width: 1.6),
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                      // Date pill, bottom-right.
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: SkeletonBlock(
                            width: 96, height: 24, radius: 7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Calendar list-area skeletons: ghost of the real rows — #222222
/// rounded-16 card, 12px padding, 72x100 radius-10 thumb, 16px w700 title,
/// 4px gap, 14px 'EP n · time' line, trailing chevron.
Widget skeletonCalendarRows(BuildContext context, {int count = 4}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GaColors.of(context).card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SkeletonBlock(width: 72, height: 100, radius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(height: 16, radius: 6),
                      SizedBox(height: 4),
                      SkeletonBlock(width: 140, height: 14, radius: 7),
                    ],
                  ),
                ),
                SkeletonBlock(width: 24, height: 24, radius: 12),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Library list skeletons: ghost of the real ListTile rows — #222222
/// rounded-16 card, 16px horizontal / 8px vertical padding, 40x56
/// radius-6 thumb, 16px title line, 12px status line, 16px title gap
/// (ListTile's horizontalTitleGap).
Widget skeletonLibraryRows(BuildContext context, {int count = 5}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: GaColors.of(context).card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SkeletonBlock(width: 40, height: 56, radius: 6),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(height: 16, radius: 6),
                      SizedBox(height: 8),
                      SkeletonBlock(width: 200, height: 12, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Profile picker skeleton: ghost of ProfilePickerScreen — 84px circles
/// in the same Wrap (spacing 24), name bars, a PRIMARY badge bar on the
/// first, an add-profile circle, and the full-width Manage Profiles bar
/// (52px, radius 14), so nothing jumps when the real picker lands.
class SkeletonPicker extends StatelessWidget {
  const SkeletonPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            // Logo row: 30px mark + 4px gap + 'nime' 18px wordmark.
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBlock(width: 30, height: 30, radius: 15),
                SizedBox(width: 4),
                SkeletonBlock(width: 56, height: 18, radius: 9),
              ],
            ),
            const SizedBox(height: 36),
            const SkeletonBlock(width: 220, height: 30, radius: 8),
            const SizedBox(height: 8),
            const SkeletonBlock(width: 180, height: 14, radius: 7),
            const SizedBox(height: 36),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < 2; i++)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SkeletonBlock(
                          width: 84, height: 84, radius: 42),
                      const SizedBox(height: 10),
                      const SkeletonBlock(
                          width: 64, height: 15, radius: 7),
                      if (i == 0) ...[
                        const SizedBox(height: 6),
                        const SkeletonBlock(
                            width: 70, height: 16, radius: 10),
                      ],
                    ],
                  ),
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonBlock(width: 84, height: 84, radius: 42),
                    SizedBox(height: 10),
                    SkeletonBlock(width: 80, height: 15, radius: 7),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 48),
            // Manage Profiles button: full-width, 52px, radius 14, #1A1A1A
            // with #333 border, 16px label.
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: GaColors.of(context).field,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFF333333)),
              ),
              child: const Center(
                child: SkeletonBlock(width: 130, height: 16, radius: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
