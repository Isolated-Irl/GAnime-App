// About & Credits settings sub-screen.
import 'package:flutter/material.dart';
import 'settings_shell.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  Widget _credit(String title, String body) {
    return GACard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: gaGrey, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'About & Credits',
      children: [
        const Text(
          'A client-side anime web app with zero backend video hosting. All catalogue metadata is retrieved directly via public GraphQL and REST APIs.',
          style: TextStyle(color: gaGrey, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 8),
        const Text(
          'Web app at ganime.pages.dev is untouched by this app.',
          style: TextStyle(color: gaGreyDark, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _credit('AniList GraphQL API',
            'Provides comprehensive anime metadata, rankings, airing schedules, and cover imagery.'),
        _credit('Kitsu API',
            "Catalogue and episode data for the app's Home, Search and Details screens."),
        _credit('ani.zip API',
            'Cross-database mappings between AniList, MyAnimeList, TVDb, and IMDb IDs.'),
        _credit('AniSkip Service',
            'Crowdsourced timestamp intervals for opening (OP) and ending (ED) skip buttons.'),
        _credit('media_kit',
            'The playback engine behind the Android app (mpv).'),
        _credit('Built with Muse & Gemini',
            'Designed and built by Isolated in a three-way collaboration — Muse (build & verification) and Gemini (analysis & benchmarking).'),
        _credit('♥ NuvioWeb Inspiration',
            'UI and player design inspired by NuvioWeb — modern glass styling, floating control pills, and a sleek dark aesthetic.'),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Made with ♥ by Isolated\nGAnime 0.1.0',
            textAlign: TextAlign.center,
            style: TextStyle(color: gaGrey, fontSize: 12, height: 1.6),
          ),
        ),
      ],
    );
  }
}
