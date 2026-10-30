import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ganime/models.dart';
import 'package:ganime/screens/streams.dart';
import 'package:ganime/widgets/glass_surface.dart';

void main() {
  testWidgets('StreamsScreen builds with episode hook params',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    const settings = AppSettings();
    const anime = Anime(id: 1, title: 'Test Anime');
    await tester.pumpWidget(MaterialApp(
      home: StreamsScreen(
        anime: anime,
        episode: 3,
        profileId: 'p1',
        settings: settings,
        episodes: const [EpisodeInfo(number: 1, title: 'Ep 1')],
        watchedEpisodes: const {1, 2},
      ),
    ));
    await tester.pump();
    // Streams screen shows its loading/empty state without crashing.
    expect(find.byType(StreamsScreen), findsOneWidget);
  });

  testWidgets('GlassSurface builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GlassSurface(
          radius: 12,
          child: SizedBox(width: 44, height: 44),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(GlassSurface), findsOneWidget);
  });
}
