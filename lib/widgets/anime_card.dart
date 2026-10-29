import 'package:flutter/material.dart';
import '../models.dart';

/// Poster art ratio, matching the website's `.poster-art` (`aspect-ratio:
/// 2 / 3`). Every poster card app-wide uses this — images crop to fill
/// (BoxFit.cover), never stretch, so all posters are identical in size.
const kPosterArtRatio = 2 / 3;

/// Vertical space reserved under the poster for the title (2 lines max) +
/// meta line + gaps. Grids/rails size their cells as
/// `imageHeight(2:3) + kPosterTextReserve` so nothing overflows and all
/// cards are uniform.
const kPosterTextReserve = 64.0;

/// Grid cell aspect ratio for a poster card of the given cell [width]:
/// fixed 2:3 art plus the reserved text block.
double posterGridChildAspectRatio(double width) =>
    width / (width / kPosterArtRatio + kPosterTextReserve);

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;
  final String? badge;
  const AnimeCard({super.key, required this.anime, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed 2:3 art (website parity). AspectRatio sizes from the
          // parent width, so every poster is identical regardless of the
          // source image's natural dimensions or the title length below.
          AspectRatio(
            aspectRatio: kPosterArtRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: anime.cover.isEmpty
                  ? Container(color: Colors.grey.shade800)
                  : Image.network(
                      anime.cover,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) =>
                          Container(color: Colors.grey.shade800),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (badge != null)
            Text(badge!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          // Web rail cards show score as ★7.5 · 2026, not 75%.
          if (anime.score != null || anime.year != null)
            Text(
              [
                if (anime.score != null)
                  '★ ${(anime.score! / 10).toStringAsFixed(1)}',
                if (anime.year != null) '${anime.year}',
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
        ],
      ),
    );
  }
}
