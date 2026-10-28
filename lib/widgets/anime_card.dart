import 'package:flutter/material.dart';
import '../models.dart';

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
          Expanded(
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
