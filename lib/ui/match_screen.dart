import 'package:flutter/material.dart';

import '../models.dart';
import '../services/library.dart';
import '../services/tmdb.dart';
import 'player_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lets the user pick the right TMDB movie or show by hand.
/// Every group key passed in gets the chosen match, so a whole TV show
/// (all seasons) is fixed in one step.
class MatchScreen extends StatefulWidget {
  final String query;
  final int? year;
  final bool tv;
  final Set<String> groupKeys;
  final String filesInfo;
  final bool alreadyMatched;

  const MatchScreen({
    super.key,
    required this.query,
    required this.groupKeys,
    this.year,
    this.tv = false,
    this.filesInfo = '',
    this.alreadyMatched = false,
  });

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late final _q = TextEditingController(text: widget.query);
  late final _y = TextEditingController(text: widget.year?.toString() ?? '');
  late bool _tv = widget.tv;
  bool _loading = false;
  String? _error;
  List<TmdbInfo> _results = [];

  @override
  void initState() {
    super.initState();
    if (widget.query.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _q.dispose();
    _y.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await TmdbApi.search(q, tv: _tv, year: int.tryParse(_y.text.trim()));
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(TmdbInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PX.surface,
        title: Text('Use "${info.title}${info.year != null ? ' (${info.year})' : ''}"?'),
        content: Text(_tv
            ? 'All files in this group will appear under this show, with their seasons and episodes.'
            : 'All files in this group will appear as this movie.'),
        actions: [
          PillButton(label: 'Cancel', onTap: () => Navigator.of(ctx).pop(false)),
          PillButton(
            label: 'Use this',
            icon: Icons.check_rounded,
            primary: true,
            autofocus: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Library.instance.setManualMatch(widget.groupKeys, _tv ? 'tv' : 'movie', info);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Matched to ${info.title}')));
    NavButtons.goHome(context);
  }

  Future<void> _undoManual() async {
    await Library.instance.setManualMatch(widget.groupKeys, 'movie', null);
    if (mounted) NavButtons.goHome(context);
  }

  Future<void> _unmatch() async {
    await Library.instance.unmatch(widget.groupKeys);
    if (mounted) NavButtons.goHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final pad = Layout.pad(context);
    final pw = Layout.posterWidth(context);
    final manual = Library.hasOverride(widget.groupKeys);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NavButtons(),
                    const SizedBox(height: 18),
                    const Text('Identify title',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                    if (widget.filesInfo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(widget.filesInfo, style: const TextStyle(color: PX.muted)),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        PillButton(
                          label: 'Movie',
                          icon: Icons.movie_rounded,
                          selected: !_tv,
                          onTap: () {
                            setState(() => _tv = false);
                            _search();
                          },
                        ),
                        PillButton(
                          label: 'TV Show',
                          icon: Icons.tv_rounded,
                          selected: _tv,
                          onTap: () {
                            setState(() => _tv = true);
                            _search();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _q,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _search(),
                              decoration: const InputDecoration(
                                labelText: 'Title',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: _y,
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _search(),
                              decoration: const InputDecoration(labelText: 'Year'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PillButton(label: 'Search', icon: Icons.search, primary: true, onTap: _search),
                        ],
                      ),
                    ),
                    if (widget.alreadyMatched || manual) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (manual)
                            PillButton(
                              label: 'Undo my manual match',
                              icon: Icons.undo_rounded,
                              onTap: _undoManual,
                            ),
                          if (widget.alreadyMatched)
                            PillButton(
                              label: 'Wrong title — move to Unmatched',
                              icon: Icons.link_off_rounded,
                              onTap: _unmatch,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (_loading) const LinearProgressIndicator(color: PX.accent, minHeight: 2),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!, style: const TextStyle(color: PX.accent)),
                      ),
                    if (!_loading && _error == null && _results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Text('No results. Try a shorter title, remove the year, or switch Movie / TV Show.',
                            style: TextStyle(color: PX.muted)),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: pw + 20,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  childAspectRatio: pw / (pw * 1.5 + 50),
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final r = _results[i];
                    return LayoutBuilder(
                      builder: (_, c) => PosterCard(
                        image: TmdbApi.poster(r.poster),
                        title: r.title,
                        caption: r.year?.toString() ?? '—',
                        width: c.maxWidth,
                        onTap: () => _pick(r),
                      ),
                    );
                  },
                  childCount: _results.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An unidentified group: its files (playable) and an Identify button.
class UnmatchedScreen extends StatelessWidget {
  final UnmatchedGroup group;
  const UnmatchedScreen({super.key, required this.group});

  void _identify(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MatchScreen(
        query: group.title,
        year: group.year,
        tv: group.isShow,
        groupKeys: {group.key},
        filesInfo: '${group.title}  •  ${group.summary}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pad = Layout.pad(context);
    final files = [...group.files]..sort((a, b) => a.fileName.compareTo(b.fileName));
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 40),
          children: [
            const Align(alignment: Alignment.centerLeft, child: NavButtons()),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(group.isShow ? Icons.tv_rounded : Icons.movie_rounded, color: PX.accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(group.title.isEmpty ? 'Unknown' : group.title,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${group.summary}  •  ${formatSize(group.size)}  •  not identified on TMDB',
                style: const TextStyle(color: PX.muted)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                label: 'Identify with TMDB',
                icon: Icons.manage_search_rounded,
                primary: true,
                autofocus: true,
                onTap: () => _identify(context),
              ),
            ),
            const SizedBox(height: 20),
            for (final f in files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FocusCard(
                  focusScale: 1.01,
                  onTap: () => PlayerScreen.open(context, [
                    PlayItem(file: f, title: group.title.isEmpty ? f.fileName : group.title, subtitle: f.fileName)
                  ]),
                  child: Container(
                    color: PX.surface,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill_rounded, color: PX.accent, size: 28),
                        const SizedBox(width: 14),
                        Expanded(child: Text(f.fileName, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 12),
                        Text(formatSize(f.size), style: const TextStyle(color: PX.muted)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
