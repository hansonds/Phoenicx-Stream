import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'parser.dart';
import 'settings.dart';
import 'tmdb.dart';
import 'torbox.dart';

enum LibraryStatus { idle, loading, ready, error }

/// Builds and holds the library: TorBox files matched to TMDB titles.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  LibraryStatus status = LibraryStatus.idle;
  String message = '';
  String? error;

  List<Movie> movies = [];
  List<Show> shows = [];
  List<UnmatchedGroup> unmatched = [];

  /// Last file list from TorBox, kept so manual matches apply instantly.
  List<MediaFile> _files = [];

  bool get isEmpty => movies.isEmpty && shows.isEmpty && unmatched.isEmpty;

  bool _busy = false;

  /// Loads the last snapshot instantly (if any), then refreshes from TorBox.
  Future<void> load() async {
    final snap = AppSettings.librarySnapshot;
    if (snap != null && isEmpty) {
      try {
        _files = (jsonDecode(snap) as List)
            .map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
            .toList();
        await _build(_files, quiet: true);
      } catch (_) {}
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    error = null;
    status = LibraryStatus.loading;
    message = 'Reading your TorBox library…';
    notifyListeners();
    try {
      final files = await TorBoxApi.fetchAllVideoFiles();
      _files = files;
      await AppSettings.saveLibrarySnapshot(jsonEncode(files.map((f) => f.toJson()).toList()));
      await _build(files);
      status = LibraryStatus.ready;
      message = '';
    } catch (e) {
      error = e.toString();
      status = isEmpty ? LibraryStatus.error : LibraryStatus.ready;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Saves a manual match for one or more groups and rebuilds right away.
  /// [kind] is 'movie' or 'tv'. Pass info = null to undo a manual match.
  Future<void> setManualMatch(Iterable<String> groupKeys, String kind, TmdbInfo? info) async {
    for (final k in groupKeys) {
      await AppSettings.setOverride(
          k, info == null ? null : {'kind': kind, 'info': info.toJson()});
    }
    await _build(_files, quiet: true);
    notifyListeners();
  }

  /// Marks groups as "not a match" so they move to Unmatched.
  Future<void> unmatch(Iterable<String> groupKeys) async {
    for (final k in groupKeys) {
      await AppSettings.setOverride(k, {'kind': 'none'});
    }
    await _build(_files, quiet: true);
    notifyListeners();
  }

  static bool hasOverride(Iterable<String> keys) =>
      keys.any((k) => AppSettings.overrides.containsKey(k));

  Future<void> _build(List<MediaFile> files, {bool quiet = false}) async {
    // Group files by parsed title so each title is looked up once.
    final movieGroups = <String, _Group>{};
    final showGroups = <String, _Group>{};
    for (final f in files) {
      final p = NameParser.parseFile(f.fileName, f.fullPath, f.itemName);
      if (p.title.isEmpty) {
        movieGroups
            .putIfAbsent('?${f.key}', () => _Group('?${f.key}', f.fileName, null, false))
            .files
            .add(_PF(f, p));
        continue;
      }
      final norm = NameParser.normalize(p.title);
      if (p.isEpisode) {
        final k = 't|$norm';
        showGroups.putIfAbsent(k, () => _Group(k, p.title, p.year, true)).files.add(_PF(f, p));
      } else {
        final k = 'm|$norm|${p.year ?? ''}';
        movieGroups.putIfAbsent(k, () => _Group(k, p.title, p.year, false)).files.add(_PF(f, p));
      }
    }

    final allGroups = [...movieGroups.values, ...showGroups.values];
    final total = allGroups.length;
    var done = 0;
    void tick() {
      done++;
      if (!quiet && (done % 5 == 0 || done == total)) {
        message = 'Matching titles with TMDB… $done / $total';
        notifyListeners();
      }
    }

    final movieMap = <int, Movie>{};
    final showMap = <int, Show>{};
    final unmatchedGroups = <UnmatchedGroup>[];

    void addAsMovie(_Group g, TmdbInfo info) {
      final m = movieMap.putIfAbsent(info.id, () => Movie(info));
      m.files.addAll(g.files.map((e) => e.file));
      m.groupKeys.add(g.key);
    }

    void addAsShow(_Group g, TmdbInfo info) {
      final s = showMap.putIfAbsent(info.id, () => Show(info));
      s.groupKeys.add(g.key);
      if (g.isShow) {
        for (final pf in g.files) {
          s.episodes.add(EpisodeFile(pf.parsed.season!, pf.parsed.episode!, pf.file));
        }
      } else {
        // Files without SxxEyy forced into a show: number them in name order.
        final sorted = [...g.files]..sort((a, b) => a.file.fileName.compareTo(b.file.fileName));
        for (var i = 0; i < sorted.length; i++) {
          s.episodes.add(EpisodeFile(1, i + 1, sorted[i].file));
        }
      }
    }

    void addUnmatched(_Group g) {
      final u = UnmatchedGroup(key: g.key, title: g.title, year: g.year, isShow: g.isShow);
      for (final pf in g.files) {
        u.files.add(pf.file);
        if (g.isShow) u.seasons.putIfAbsent(pf.parsed.season!, () => {}).add(pf.parsed.episode!);
      }
      unmatchedGroups.add(u);
    }

    final tasks = <Future<void> Function()>[];
    for (final g in allGroups) {
      tasks.add(() async {
        // 1. A match the user picked by hand always wins.
        final o = AppSettings.overrides[g.key];
        if (o is Map) {
          final kind = o['kind'];
          if (kind == 'none') {
            addUnmatched(g);
          } else if (o['info'] is Map) {
            final info = TmdbInfo.fromJson(Map<String, dynamic>.from(o['info'] as Map));
            if (kind == 'tv') {
              addAsShow(g, info);
            } else {
              addAsMovie(g, info);
            }
          } else {
            addUnmatched(g);
          }
          tick();
          return;
        }
        // 2. Automatic TMDB search.
        TmdbInfo? info;
        if (!g.key.startsWith('?')) {
          try {
            info = g.isShow
                ? await TmdbApi.findShow(g.title, g.year)
                : await TmdbApi.findMovie(g.title, g.year);
          } catch (_) {}
        }
        if (info == null) {
          addUnmatched(g);
        } else if (g.isShow) {
          addAsShow(g, info);
        } else {
          addAsMovie(g, info);
        }
        tick();
      });
    }

    await _runPool(tasks, 6);
    await AppSettings.saveMatchCache();

    movies = movieMap.values.toList()..sort((a, b) => b.added.compareTo(a.added));
    shows = showMap.values.toList()..sort((a, b) => b.added.compareTo(a.added));
    for (final s in shows) {
      s.episodes.sort((a, b) {
        final c = a.season.compareTo(b.season);
        return c != 0 ? c : a.episode.compareTo(b.episode);
      });
    }
    unmatched = unmatchedGroups..sort((a, b) => b.added.compareTo(a.added));
    if (quiet) {
      status = LibraryStatus.ready;
      notifyListeners();
    }
  }

  static Future<void> _runPool(List<Future<void> Function()> tasks, int size) async {
    var i = 0;
    Future<void> worker() async {
      while (i < tasks.length) {
        final t = tasks[i++];
        await t();
      }
    }

    await Future.wait(List.generate(size, (_) => worker()));
  }

  /// Rebuilds after clearing automatic TMDB matches (manual ones are kept).
  Future<void> rematch() async {
    await AppSettings.clearMatchCache();
    movies = [];
    shows = [];
    unmatched = [];
    await refresh();
  }
}

class _PF {
  final MediaFile file;
  final ParsedName parsed;
  _PF(this.file, this.parsed);
}

class _Group {
  final String key;
  final String title;
  final int? year;
  final bool isShow;
  final List<_PF> files = [];
  _Group(this.key, this.title, this.year, this.isShow);
}
