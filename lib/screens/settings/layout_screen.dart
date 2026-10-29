// Layout settings sub-screen (Settings > Layout) — website parity.
// All rows persist to AppSettings via Store.saveSettings and notify onSettings.
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../store.dart';
import 'settings_shell.dart';

class LayoutSettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const LayoutSettingsScreen(
      {super.key, required this.settings, required this.onSettings});

  @override
  State<LayoutSettingsScreen> createState() => _LayoutSettingsScreenState();
}

class _LayoutSettingsScreenState extends State<LayoutSettingsScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  Widget _swatch(({String value, String label, Color color}) t) {
    final selected = _s.theme == t.value;
    return InkWell(
      onTap: () => _save(_s.copyWith(theme: t.value)),
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.color,
                  border: Border.all(
                    color: selected ? gaGreen : gaCardBorder,
                    width: 2,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: gaGreen,
                  ),
                  child: const Icon(Icons.check,
                      color: Colors.white, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : gaGrey,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: selected ? t.color : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  void _push(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Layout',
      children: [
        gaSectionLabel('Theme'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in gaThemes) _swatch(t)],
        ),
        gaSectionLabel('Display'),
        gaToggleRow(
          title: 'AMOLED Black',
          value: _s.amoledBlack,
          onChanged: (v) => _save(_s.copyWith(amoledBlack: v)),
        ),
        gaDropdownRow(
          context: context,
          title: 'Navigation Bar Position',
          value: _s.navBarPosition,
          options: const {'bottom': 'bottom'},
          onChanged: (v) => _save(_s.copyWith(navBarPosition: v)),
        ),
        gaToggleRow(
          title: 'Liquid Glass Tab Bar',
          value: _s.liquidGlassTabBar,
          onChanged: (v) => _save(_s.copyWith(liquidGlassTabBar: v)),
        ),
        gaSectionLabel('Home & Details'),
        gaDropdownRow(
          context: context,
          title: 'Hero Style',
          value: _s.heroStyle,
          options: const {'full_bleed': 'full_bleed'},
          onChanged: (v) => _save(_s.copyWith(heroStyle: v)),
        ),
        gaToggleRow(
          title: 'Hero Trailer Autoplay',
          value: _s.heroTrailerAutoplay,
          onChanged: (v) => _save(_s.copyWith(heroTrailerAutoplay: v)),
        ),
        gaToggleRow(
          title: 'Hero Trailer Sound',
          value: _s.heroTrailerSound,
          onChanged: (v) => _save(_s.copyWith(heroTrailerSound: v)),
        ),
        gaDropdownRow(
          context: context,
          title: 'Hero Trailer Delay',
          value: _s.heroTrailerDelay,
          options: const {'Instant': 'Instant'},
          onChanged: (v) => _save(_s.copyWith(heroTrailerDelay: v)),
        ),
        gaToggleRow(
          title: 'Dynamic Background Colour',
          value: _s.dynamicBackground,
          onChanged: (v) => _save(_s.copyWith(dynamicBackground: v)),
        ),
        gaToggleRow(
          title: 'Catalog Accent Underline',
          value: _s.catalogAccentUnderline,
          onChanged: (v) => _save(_s.copyWith(catalogAccentUnderline: v)),
        ),
        gaToggleRow(
          title: 'Budget & Revenue on Details',
          value: _s.budgetRevenueOnDetails,
          onChanged: (v) => _save(_s.copyWith(budgetRevenueOnDetails: v)),
        ),
        gaToggleRow(
          title: 'Icon Action Row on Details',
          value: _s.iconActionRowOnDetails,
          onChanged: (v) => _save(_s.copyWith(iconActionRowOnDetails: v)),
        ),
        gaChevronRow(
          title: 'Home Layout',
          onTap: () => _push(
              _RailTogglesPage(settings: _s, onSettings: (s) => _save(s))),
        ),
        gaChevronRow(
          title: 'Collections',
          onTap: () => _push(const _NotePage(
            title: 'Collections',
            body: "Collections aren't available in the Android app yet.",
          )),
        ),
        gaChevronRow(
          title: 'Continue Watching',
          onTap: () => _push(
              _ContinueWatchingPage(settings: _s, onSettings: (s) => _save(s))),
        ),
        gaChevronRow(
          title: 'Poster Card Style',
          onTap: () => _push(const _NotePage(
            title: 'Poster Card Style',
            body: "Poster cards use the app's default style.",
          )),
        ),
        gaSectionLabel('Streams'),
        gaChevronRow(
          title: 'Streams',
          onTap: () => _push(const _NotePage(
            title: 'Streams',
            body:
                'Streams come from your own installed addons — the app ships with none. Manage them under Settings > Addon.',
          )),
        ),
        gaSectionLabel('Detail Page'),
        gaChevronRow(
          title: 'Detail Page',
          onTap: () => _push(
              _DetailPageOptions(settings: _s, onSettings: (s) => _save(s))),
        ),
      ],
    );
  }
}

/// Tiny note page for not-yet-available website-parity sections.
class _NotePage extends StatelessWidget {
  final String title;
  final String body;
  const _NotePage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: title,
      children: [
        GACard(
          child: Text(
            body,
            style: const TextStyle(color: gaGrey, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// Home Layout page: hero + rail visibility toggles.
class _RailTogglesPage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const _RailTogglesPage({required this.settings, required this.onSettings});

  @override
  State<_RailTogglesPage> createState() => _RailTogglesPageState();
}

class _RailTogglesPageState extends State<_RailTogglesPage> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Home Layout',
      children: [
        gaToggleRow(
          title: 'Hero carousel',
          value: _s.showHero,
          onChanged: (v) => _save(_s.copyWith(showHero: v)),
        ),
        gaToggleRow(
          title: 'Continue Watching rail',
          value: _s.showContinueWatching,
          onChanged: (v) => _save(_s.copyWith(showContinueWatching: v)),
        ),
        gaToggleRow(
          title: 'Trending Now rail',
          value: _s.railTrending,
          onChanged: (v) => _save(_s.copyWith(railTrending: v)),
        ),
        gaToggleRow(
          title: 'Popular This Season rail',
          value: _s.railPopularSeason,
          onChanged: (v) => _save(_s.copyWith(railPopularSeason: v)),
        ),
        gaToggleRow(
          title: 'Upcoming Next Season rail',
          value: _s.railUpcoming,
          onChanged: (v) => _save(_s.copyWith(railUpcoming: v)),
        ),
        gaToggleRow(
          title: 'All Time Popular rail',
          value: _s.railAllTime,
          onChanged: (v) => _save(_s.copyWith(railAllTime: v)),
        ),
        gaToggleRow(
          title: 'Top 100 Anime rail',
          value: _s.railTop100,
          onChanged: (v) => _save(_s.copyWith(railTop100: v)),
        ),
        gaToggleRow(
          title: 'Top 100 Movies rail',
          value: _s.railTopMovies,
          onChanged: (v) => _save(_s.copyWith(railTopMovies: v)),
        ),
      ],
    );
  }
}

/// Continue Watching sub-page: rail toggle + explanatory note.
class _ContinueWatchingPage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const _ContinueWatchingPage(
      {required this.settings, required this.onSettings});

  @override
  State<_ContinueWatchingPage> createState() => _ContinueWatchingPageState();
}

class _ContinueWatchingPageState extends State<_ContinueWatchingPage> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Continue Watching',
      children: [
        gaToggleRow(
          title: 'Continue Watching rail',
          value: _s.showContinueWatching,
          onChanged: (v) => _save(_s.copyWith(showContinueWatching: v)),
        ),
        const GACard(
          child: Text(
            'Show or hide the Continue Watching rail on Home.',
            style: TextStyle(color: gaGrey, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Detail Page sub-page: budget/revenue and icon action row toggles.
class _DetailPageOptions extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const _DetailPageOptions({required this.settings, required this.onSettings});

  @override
  State<_DetailPageOptions> createState() => _DetailPageOptionsState();
}

class _DetailPageOptionsState extends State<_DetailPageOptions> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Detail Page',
      children: [
        gaToggleRow(
          title: 'Budget & Revenue on Details',
          value: _s.budgetRevenueOnDetails,
          onChanged: (v) => _save(_s.copyWith(budgetRevenueOnDetails: v)),
        ),
        gaToggleRow(
          title: 'Icon Action Row on Details',
          value: _s.iconActionRowOnDetails,
          onChanged: (v) => _save(_s.copyWith(iconActionRowOnDetails: v)),
        ),
      ],
    );
  }
}
