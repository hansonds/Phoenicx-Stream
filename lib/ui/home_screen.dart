import 'package:flutter/material.dart';

import '../models.dart';
import '../services/library.dart';
import '../services/settings.dart';
import '../services/tmdb.dart';
import 'detail_screens.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Tab { home, movies, shows, other, search }

/// Either a movie or a show, for mixed rows.
class _Entry {
  final Movie? movie;
  final Show? show;
  _Entry.movie(this.movie) : show = null;
  _Entry.show(this.show) : movie = null;
  TmdbInfo get info => movie?.info ?? show!.info;
  DateTime get added => movie?.added ?? show!.added;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final lib = Library.instance;
  _Tab _tab = _Tab.home;
  final _hero = ValueNotifier<TmdbInfo?>(null);
  String _sort = 'recent';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    lib.addListener(_onLib);
    if (lib.status == LibraryStatus.idle) lib.load();
  }

  @override
  void dispose() {
    lib.removeListener(_onLib);
    _hero.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onLib() {
    if (mounted) setState(() {});
  }

  void _openEntry(_Entry e) {
    _openInfo(e.movie, e.show);
  }

  Future<void> _openInfo(Movie? m, Show? s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => m != null ? MovieScreen(movie: m) : ShowScreen(show: s!),
    ));
    if (mounted) setState(() {}); // refresh continue watching
  }

  List<_Entry> get _recent {
    final all = [
      ...lib.movies.map(_Entry.movie),
      ...lib.shows.map(_Entry.show),
    ]..sort((a, b) => b.added.compareTo(a.added));
    return all;
  }

  // ---------- continue watching ----------
  List<MapEntry<String, Map>> get _continue {
    final list = AppSettings.progress.entries
        .where((e) => e.value is Map && (e.value as Map)['file'] is Map)
        .map((e) => MapEntry(e.key, e.value as Map))
        .toList()
      ..sort((a, b) => ((b.value['t'] ?? 0) as int).compareTo((a.value['t'] ?? 0) as int));
    return list.take(20).toList();
  }

  Future<void> _resume(Map entry) async {
    final file = MediaFile.fromJson(Map<String, dynamic>.from(entry['file'] as Map));
    // If it's an episode of a known show, play with the rest of the show queued.
    for (final s in lib.shows) {
      final idx = s.episodes.indexWhere((e) => e.file.key == file.key);
      if (idx >= 0) {
        final list = <PlayItem>[];
        var start = 0;
        for (final season in s.seasons) {
          for (final ep in s.episodesOf(season).entries) {
            final chosen = ep.value.firstWhere((v) => v.file.key == file.key, orElse: () => ep.value.first);
            if (chosen.file.key == file.key) start = list.length;
            list.add(PlayItem(
              file: chosen.file,
              title: s.info.title,
              subtitle: 'S${season.toString().padLeft(2, '0')}E${ep.key.toString().padLeft(2, '0')}',
              image: TmdbApi.backdrop(s.info.backdrop, size: 'w780'),
            ));
          }
        }
        await PlayerScreen.open(context, list, index: start);
        if (mounted) setState(() {});
        return;
      }
    }
    await PlayerScreen.open(context, [
      PlayItem(
        file: file,
        title: (entry['title'] ?? file.fileName).toString(),
        subtitle: (entry['subtitle'] ?? '').toString(),
        image: entry['image'] as String?,
      )
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _removeContinue(String key) async {
    await AppSettings.removeProgress(key);
    if (mounted) setState(() {});
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            if (lib.status == LibraryStatus.loading && !lib.isEmpty)
              LinearProgressIndicator(minHeight: 2, color: PX.accent, backgroundColor: PX.bg),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final pad = Layout.pad(context);
    Widget tab(_Tab t, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: PillButton(
            label: label,
            icon: icon,
            selected: _tab == t,
            onTap: () => setState(() => _tab = t),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 6),
      child: Row(
        children: [
          Image.asset('assets/logo.png', width: 34, height: 34),
          const SizedBox(width: 10),
          if (Layout.wide(context))
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Text('PHOENICX STREAM',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  tab(_Tab.home, 'Home', Icons.home_rounded),
                  tab(_Tab.movies, 'Movies', Icons.movie_rounded),
                  tab(_Tab.shows, 'TV Shows', Icons.tv_rounded),
                  if (lib.others.isNotEmpty) tab(_Tab.other, 'Other', Icons.folder_rounded),
                  tab(_Tab.search, 'Search', Icons.search_rounded),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillButton(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: () => lib.refresh(),
                    ),
                  ),
                  PillButton(
                    label: 'Settings',
                    icon: Icons.settings_rounded,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (lib.isEmpty) {
      if (lib.status == LibraryStatus.error) {
        return _message(
          Icons.cloud_off_rounded,
          'Could not load your library',
          lib.error ?? '',
          actions: [
            PillButton(label: 'Retry', icon: Icons.refresh, primary: true, autofocus: true,
                onTap: () => lib.refresh()),
            PillButton(
                label: 'Settings',
                icon: Icons.settings,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ],
        );
      }
      if (lib.status == LibraryStatus.ready) {
        return _message(Icons.inbox_rounded, 'Your TorBox library is empty',
            'Add some torrents on torbox.app, then press Refresh.',
            actions: [
              PillButton(label: 'Refresh', icon: Icons.refresh, primary: true, autofocus: true,
                  onTap: () => lib.refresh()),
            ]);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: PX.accent),
            const SizedBox(height: 18),
            Text(lib.message, style: const TextStyle(color: PX.muted)),
          ],
        ),
      );
    }
    switch (_tab) {
      case _Tab.home:
        return _homeTab();
      case _Tab.movies:
        return _gridTab(lib.movies.map(_Entry.movie).toList());
      case _Tab.shows:
        return _gridTab(lib.shows.map(_Entry.show).toList());
      case _Tab.other:
        return _otherTab();
      case _Tab.search:
        return _searchTab();
    }
  }

  Widget _message(IconData icon, String title, String text, {List<Widget> actions = const []}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: PX.accent),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: PX.muted)),
            const SizedBox(height: 18),
            Wrap(spacing: 12, children: actions),
          ],
        ),
      ),
    );
  }

  // ---------- Home tab ----------
  Widget _homeTab() {
    final recent = _recent;
    final cont = _continue;
    final pw = Layout.posterWidth(context);
    final posterRowH = pw * 1.5 + 64;
    final wideW = pw * 1.9;
    final wideRowH = wideW * 9 / 16 + 64;
    final wide = Layout.wide(context);
    if (_hero.value == null && recent.isNotEmpty) _hero.value = recent.first.info;

    Widget posterRow(String title, List<_Entry> items) => ShelfRow(
          title: title,
          height: posterRowH,
          itemCount: items.length,
          itemBuilder: (_, i) {
            final e = items[i];
            return PosterCard(
              image: TmdbApi.poster(e.info.poster),
              title: e.info.title,
              caption: e.info.year?.toString(),
              width: pw,
              onTap: () => _openEntry(e),
              onFocus: (f) {
                if (f) _hero.value = e.info;
              },
            );
          },
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        if (recent.isNotEmpty) _heroView(wide, recent.first),
        if (cont.isNotEmpty)
          ShelfRow(
            title: 'Continue Watching',
            height: wideRowH,
            itemCount: cont.length,
            itemBuilder: (_, i) {
              final e = cont[i];
              final pos = (e.value['pos'] ?? 0) as int;
              final dur = (e.value['dur'] ?? 0) as int;
              return WideCard(
                image: e.value['image'] as String?,
                title: (e.value['title'] ?? '').toString(),
                caption: '${e.value['subtitle'] ?? ''}  •  ${formatDuration(Duration(milliseconds: dur - pos))} left',
                width: wideW,
                progress: dur > 0 ? pos / dur : null,
                onTap: () => _resume(e.value),
                onLongPress: () => _removeContinue(e.key),
              );
            },
          ),
        if (recent.isNotEmpty) posterRow('Recently Added', recent.take(25).toList()),
        if (lib.movies.isNotEmpty) posterRow('Movies', lib.movies.take(30).map(_Entry.movie).toList()),
        if (lib.shows.isNotEmpty) posterRow('TV Shows', lib.shows.take(30).map(_Entry.show).toList()),
        if (lib.error != null)
          Padding(
            padding: EdgeInsets.all(Layout.pad(context)),
            child: Text('Last refresh failed: ${lib.error}', style: const TextStyle(color: PX.muted)),
          ),
      ],
    );
  }

  Widget _heroView(bool wide, _Entry featured) {
    final size = MediaQuery.sizeOf(context);
    final pad = Layout.pad(context);
    final h = wide ? size.height * 0.42 : size.width * 0.62;
    return ValueListenableBuilder<TmdbInfo?>(
      valueListenable: _hero,
      builder: (_, info, __) {
        final i = info ?? featured.info;
        return SizedBox(
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: KeyedSubtree(
                  key: ValueKey(i.id),
                  child: NetImg(TmdbApi.backdrop(i.backdrop) ?? TmdbApi.poster(i.poster, size: 'w780')),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, PX.bg],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              if (wide)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xEE09090D), Colors.transparent],
                      stops: [0, 0.65],
                    ),
                  ),
                ),
              Positioned(
                left: pad,
                bottom: 12,
                right: wide ? size.width * 0.4 : pad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(i.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: wide ? 38 : 24, fontWeight: FontWeight.w900, height: 1.05)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (i.year != null) '${i.year}',
                        if (i.rating > 0) '★ ${i.rating.toStringAsFixed(1)}',
                      ].join('   •   '),
                      style: const TextStyle(color: PX.accent2, fontWeight: FontWeight.w600),
                    ),
                    if (wide) ...[
                      const SizedBox(height: 8),
                      Text(i.overview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- Movies / Shows grid ----------
  Widget _gridTab(List<_Entry> items) {
    final sorted = [...items];
    switch (_sort) {
      case 'az':
        sorted.sort((a, b) => a.info.title.toLowerCase().compareTo(b.info.title.toLowerCase()));
        break;
      case 'rating':
        sorted.sort((a, b) => b.info.rating.compareTo(a.info.rating));
        break;
      default:
        sorted.sort((a, b) => b.added.compareTo(a.added));
    }
    final pad = Layout.pad(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${sorted.length} titles', style: const TextStyle(color: PX.muted)),
                const SizedBox(width: 8),
                for (final s in const [('recent', 'Recently added'), ('az', 'A–Z'), ('rating', 'Rating')])
                  PillButton(
                    label: s.$2,
                    selected: _sort == s.$1,
                    onTap: () => setState(() => _sort = s.$1),
                  ),
              ],
            ),
          ),
        ),
        _posterGrid(sorted),
      ],
    );
  }

  Widget _posterGrid(List<_Entry> items) {
    final pw = Layout.posterWidth(context);
    final pad = Layout.pad(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: pw + 20,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: pw / (pw * 1.5 + 50),
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final e = items[i];
            return LayoutBuilder(
              builder: (_, c) => PosterCard(
                image: TmdbApi.poster(e.info.poster),
                title: e.info.title,
                caption: e.info.year?.toString(),
                width: c.maxWidth,
                onTap: () => _openEntry(e),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  // ---------- Other ----------
  Widget _otherTab() {
    final pad = Layout.pad(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Files that could not be matched on TMDB',
              style: TextStyle(color: PX.muted)),
        ),
        for (final f in lib.others)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FocusCard(
              focusScale: 1.01,
              onTap: () async {
                await PlayerScreen.open(context, [PlayItem(file: f, title: f.fileName)]);
                if (mounted) setState(() {});
              },
              child: Container(
                color: PX.surface,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, color: PX.accent, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (f.itemName.isNotEmpty && f.itemName != f.fileName)
                            Text(f.itemName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PX.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatSize(f.size), style: const TextStyle(color: PX.muted)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------- Search ----------
  Widget _searchTab() {
    final q = _search.text.trim().toLowerCase();
    final results = q.isEmpty
        ? <_Entry>[]
        : _recent.where((e) => e.info.title.toLowerCase().contains(q)).toList();
    final pad = Layout.pad(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
          sliver: SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search your movies and shows',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
        if (q.isNotEmpty && results.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No matches', style: TextStyle(color: PX.muted))),
            ),
          ),
        _posterGrid(results),
      ],
    );
  }
}
