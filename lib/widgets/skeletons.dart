import 'package:flutter/material.dart';

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
Widget skeletonPosterCard({double? width}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SkeletonBlock(width: width, height: (width ?? 120) * 1.35, radius: 10),
      const SizedBox(height: 6),
      const SkeletonBlock(height: 12, radius: 6),
      const SizedBox(height: 4),
      const SkeletonBlock(width: 64, height: 10, radius: 5),
    ],
  );
}

/// Home rail skeleton: title row + horizontal poster placeholders.
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
                  width: title.length * 8.0 + 40, height: 14, radius: 7),
              const SkeletonBlock(width: 60, height: 14, radius: 7),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, _) =>
                SizedBox(width: 120, child: skeletonPosterCard(width: 120)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

/// Hero banner skeleton (Home initial load): rounded banner + dots row.
Widget skeletonHero() {
  return Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        children: [
          const SkeletonBlock(height: 320, radius: 20),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < 4; i++) ...[
                const SkeletonBlock(width: 8, height: 8, radius: 4),
                if (i < 3) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

/// Poster grid skeleton (Search results loading): 3-column grid like AnimeGrid.
Widget skeletonPosterGrid({int count = 9}) {
  return Skeleton(
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: count,
      // The poster block flexes to fill the cell (like AnimeCard's Expanded
      // image) so the skeleton never overflows the grid cell.
      itemBuilder: (_, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SkeletonBlock(radius: 10)),
          SizedBox(height: 6),
          SkeletonBlock(height: 12, radius: 6),
          SizedBox(height: 4),
          SkeletonBlock(width: 64, height: 10, radius: 5),
        ],
      ),
    ),
  );
}

/// Detailed episode card skeletons (Details > Episodes, 'detailed' layout):
/// 16:9 still block + badge + title + synopsis lines + runtime/date footer.
Widget skeletonEpisodeDetailed({int count = 3}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: const Color(0xFF1C1C1C),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBlock(height: 170, radius: 0),
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBlock(width: 64, height: 18, radius: 8),
                          SizedBox(height: 8),
                          SkeletonBlock(height: 16, radius: 6),
                          SizedBox(height: 6),
                          SkeletonBlock(height: 12, radius: 6),
                          SizedBox(height: 4),
                          SkeletonBlock(width: 220, height: 12, radius: 6),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              SkeletonBlock(width: 40, height: 12, radius: 6),
                              Spacer(),
                              SkeletonBlock(width: 90, height: 12, radius: 6),
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
      ],
    ),
  );
}

/// Minimum episode row skeletons (Details > Episodes, 'minimum' layout):
/// 72x40 thumb + title/subtitle lines + trailing circle.
Widget skeletonEpisodeMinimum({int count = 5}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                SkeletonBlock(width: 72, height: 40, radius: 6),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(height: 14, radius: 6),
                      SizedBox(height: 6),
                      SkeletonBlock(width: 170, height: 12, radius: 6),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBlock(width: 24, height: 24, radius: 12),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Calendar list-area skeletons: 72x100 thumb + title + EP/time lines in the
/// same #222222 rounded-16 card the real rows use.
Widget skeletonCalendarRows({int count = 4}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
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
                      SizedBox(height: 8),
                      SkeletonBlock(width: 140, height: 13, radius: 6),
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

/// Library list skeletons: 40x56 thumb + title + status lines in the same
/// #222222 rounded-16 card the real rows use.
Widget skeletonLibraryRows({int count = 5}) {
  return Skeleton(
    child: Column(
      children: [
        for (int i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SkeletonBlock(width: 40, height: 56, radius: 6),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(height: 15, radius: 6),
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
