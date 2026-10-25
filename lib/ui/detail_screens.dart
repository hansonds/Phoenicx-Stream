import 'package:flutter/material.dart';

import '../models.dart';
import '../services/settings.dart';
import '../services/tmdb.dart';
import 'player_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Big backdrop header used by both detail screens.
class _Header extends StatelessWidget {
  final TmdbInfo info;
  final String meta;
  final List<Widget> buttons;
  const _Header({required this.info, required this.meta, required this.buttons});

  @override
  Widget build(BuildContext context) {
    final wide = Layout.wide(context);
    final pad = Layout.pad(context);
    final size = MediaQuery.sizeOf(context);
    final height = wide ? size.height * 0.62 : size.width * 0.9 + 140;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImg(TmdbApi.backdrop(info.backdrop) ?? TmdbApi.poster(info.poster, size: 'w780')),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x3309090D), PX.bg],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          if (wide)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xE609090D), Colors.transparent],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          Positioned(
            left: pad,
            right: pad,
            bottom: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.only(right: 28),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 180,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: NetImg(TmdbApi.poster(info.poster), fallbackText: info.title),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(info.title,
                          style: TextStyle(
                            fontSize: wide ? 40 : 28,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          )),
                      const SizedBox(height: 8),
                      Text(meta, style: const TextStyle(color: PX.accent2, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(info.overview,
                            maxLines: wide ? 4 : 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: PX.text, height: 1.4)),
                      ),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: buttons),
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
}

String _meta(TmdbInfo i, [String extra = '']) {
  final parts = <String>[
    if (i.year != null) '${i.year}',
    if (i.rating > 0) '★ ${i.rating.toStringAsFixed(1)}',
    if (extra.isNotEmpty) extra,
  ];
  return parts.join('   •   ');
}

Future<bool?> askResume(BuildContext context, Duration at) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PX.surface,
      title: const Text('Continue watching?'),
      content: Text('You stopped at ${formatDuration(at)}.'),
      actions: [
        PillButton(
            label: 'Start over', icon: Icons.replay, onTap: () => Navigator.of(ctx).pop(false)),
        PillButton(
            label: 'Resume',
            icon: Icons.play_arrow_rounded,
            primary: true,
            autofocus: true,
            onTap: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
}

/// Plays a list, asking to resume when there's saved progress.
Future<void> playWithResume(BuildContext context, List<PlayItem> list, int index) async {
  final saved = AppSettings.positionOf(list[index].file.key);
  var resume = true;
  if (saved != null && saved > const Duration(seconds: 30)) {
    final r = await askResume(context, saved);
    if (r == null) return;
    resume = r;
  }
  if (!context.mounted) return;
  await PlayerScreen.open(context, list, index: index, resume: resume);
}

// ====================================================================
// Movie
// ====================================================================

class MovieScreen extends StatefulWidget {
  final Movie movie;
  const MovieScreen({super.key, required this.movie});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  PlayItem _itemFor(MediaFile f) => PlayItem(
        file: f,
        title: widget.movie.info.title,
        subtitle: widget.movie.info.year?.toString() ?? '',
        image: TmdbApi.backdrop(widget.movie.info.backdrop, size: 'w780') ??
            TmdbApi.poster(widget.movie.info.poster),
      );

  Future<void> _play(MediaFile f) async {
    await playWithResume(context, [_itemFor(f)], 0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    final files = [...m.files]..sort((a, b) => b.size.compareTo(a.size));
    final pad = Layout.pad(context);
    final first = files.first;
    final saved = AppSettings.positionOf(first.key);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(
            info: m.info,
            meta: _meta(m.info, files.length > 1 ? '${files.length} versions' : formatSize(first.size)),
            buttons: [
              PillButton(
                label: saved != null ? 'Resume ${formatDuration(saved)}' : 'Play',
                icon: Icons.play_arrow_rounded,
                primary: true,
                autofocus: true,
                onTap: () => _play(first),
              ),
              PillButton(
                label: 'Back',
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (files.length > 1)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 8),
              child: const Text('Versions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          if (files.length > 1)
            for (final f in files)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
                child: _FileTile(file: f, onTap: () => _play(f)),
              ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final MediaFile file;
  final VoidCallback onTap;
  const _FileTile({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FocusCard(
      onTap: onTap,
      focusScale: 1.01,
      child: Container(
        color: PX.surface,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded, color: PX.accent, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(file.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Text(formatSize(file.size), style: const TextStyle(color: PX.muted)),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Show
// ====================================================================

class ShowScreen extends StatefulWidget {
  final Show show;
  const ShowScreen({super.key, required this.show});

  @override
  State<ShowScreen> createState() => _ShowScreenState();
}

class _ShowScreenState extends State<ShowScreen> {
  late int _season;
  Map<int, TmdbEpisode> _tmdbEps = {};
  bool _loadingEps = false;

  @override
  void initState() {
    super.initState();
    final seasons = widget.show.seasons;
    // Start on the season of the most recent progress, else the first season.
    _season = seasons.first;
    var best = 0;
    for (final e in widget.show.episodes) {
      final p = AppSettings.progress[e.file.key];
      if (p is Map && ((p['t'] ?? 0) as int) > best) {
        best = p['t'] as int;
        _season = e.season;
      }
    }
    _loadSeason();
  }

  Future<void> _loadSeason() async {
    setState(() => _loadingEps = true);
    try {
      final eps = await TmdbApi.season(widget.show.info.id, _season);
      if (!mounted) return;
      setState(() => _tmdbEps = {for (final e in eps) e.number: e});
    } catch (_) {
      if (mounted) setState(() => _tmdbEps = {});
    } finally {
      if (mounted) setState(() => _loadingEps = false);
    }
  }

  String _code(int s, int e) => 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';

  /// All episodes of the show (first version of each) in order, for auto-next.
  List<PlayItem> _playlist() {
    final list = <PlayItem>[];
    for (final s in widget.show.seasons) {
      final eps = widget.show.episodesOf(s);
      for (final entry in eps.entries) {
        final f = entry.value.first.file;
        final t = s == _season ? _tmdbEps[entry.key] : null;
        list.add(PlayItem(
          file: f,
          title: widget.show.info.title,
          subtitle: '${_code(s, entry.key)}${t != null && t.name.isNotEmpty ? '  •  ${t.name}' : ''}',
          image: TmdbApi.backdrop(t?.still, size: 'w780') ??
              TmdbApi.backdrop(widget.show.info.backdrop, size: 'w780'),
        ));
      }
    }
    return list;
  }

  Future<void> _playEpisode(EpisodeFile ef) async {
    final list = _playlist();
    final idx = list.indexWhere((p) => p.file.key == ef.file.key);
    if (idx < 0) {
      // A non-first version was chosen: play just that file.
      await playWithResume(context, [
        PlayItem(
          file: ef.file,
          title: widget.show.info.title,
          subtitle: _code(ef.season, ef.episode),
          image: TmdbApi.backdrop(widget.show.info.backdrop, size: 'w780'),
        )
      ], 0);
    } else {
      await playWithResume(context, list, idx);
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseVersion(List<EpisodeFile> versions) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PX.surface,
        title: const Text('Choose version'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final v in versions)
                ListTile(
                  autofocus: v == versions.first,
                  title: Text(v.file.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(formatSize(v.file.size)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _playEpisode(v);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Next episode to watch: in-progress one, else first unwatched after the
  /// last one played, else the first episode.
  EpisodeFile _nextUp() {
    final eps = widget.show.episodes;
    var bestT = 0;
    EpisodeFile? last;
    for (final e in eps) {
      final p = AppSettings.progress[e.file.key];
      if (p is Map && ((p['t'] ?? 0) as int) > bestT) {
        bestT = p['t'] as int;
        last = e;
      }
    }
    return last ?? eps.first;
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.show;
    final pad = Layout.pad(context);
    final seasons = show.seasons;
    final eps = show.episodesOf(_season);
    final next = _nextUp();
    final nextSaved = AppSettings.positionOf(next.file.key);
    final count = show.episodes.map((e) => '${e.season}-${e.episode}').toSet().length;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(
            info: show.info,
            meta: _meta(show.info, '${seasons.length} season${seasons.length == 1 ? '' : 's'} • $count episodes'),
            buttons: [
              PillButton(
                label: '${nextSaved != null ? 'Resume' : 'Play'} ${_code(next.season, next.episode)}',
                icon: Icons.play_arrow_rounded,
                primary: true,
                autofocus: true,
                onTap: () => _playEpisode(next),
              ),
              PillButton(
                label: 'Back',
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => PillButton(
                label: 'Season ${seasons[i]}',
                selected: seasons[i] == _season,
                onTap: () {
                  if (seasons[i] == _season) return;
                  setState(() {
                    _season = seasons[i];
                    _tmdbEps = {};
                  });
                  _loadSeason();
                },
              ),
            ),
          ),
          if (_loadingEps)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(color: PX.accent, minHeight: 2),
            ),
          for (final entry in eps.entries)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 7),
              child: _EpisodeTile(
                code: _code(_season, entry.key),
                tmdb: _tmdbEps[entry.key],
                versions: entry.value,
                fallbackImage: TmdbApi.backdrop(show.info.backdrop, size: 'w780'),
                onTap: () => entry.value.length > 1
                    ? _chooseVersion(entry.value)
                    : _playEpisode(entry.value.first),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final String code;
  final TmdbEpisode? tmdb;
  final List<EpisodeFile> versions;
  final String? fallbackImage;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _EpisodeTile({
    required this.code,
    required this.tmdb,
    required this.versions,
    required this.fallbackImage,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final wide = Layout.wide(context);
    final f = versions.first.file;
    final p = AppSettings.progress[f.key];
    double? progress;
    if (p is Map && ((p['dur'] ?? 0) as int) > 0) {
      progress = ((p['pos'] as int) / (p['dur'] as int)).clamp(0.0, 1.0);
    }
    final name = tmdb?.name.isNotEmpty == true ? tmdb!.name : f.fileName;
    return FocusCard(
      onTap: onTap,
      onLongPress: onLongPress,
      focusScale: 1.015,
      child: Container(
        color: PX.surface,
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: wide ? 240 : 140,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImg(TmdbApi.backdrop(tmdb?.still, size: 'w300') ?? fallbackImage,
                          fallbackIcon: Icons.tv),
                      if (progress != null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Colors.black54,
                            color: PX.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(code, style: const TextStyle(color: PX.accent2, fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  if (tmdb != null && tmdb!.overview.isNotEmpty)
                    Text(tmdb!.overview,
                        maxLines: wide ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PX.muted, fontSize: 13, height: 1.35)),
                  const SizedBox(height: 4),
                  Text(
                    '${formatSize(f.size)}${versions.length > 1 ? '  •  ${versions.length} versions' : ''}',
                    style: const TextStyle(color: PX.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
