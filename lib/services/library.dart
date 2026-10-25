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
  List<MediaFile> others = [];

  bool get isEmpty => movies.isEmpty && shows.isEmpty && others.isEmpty;

  bool _busy = false;

  /// Loads the last snapshot instantly (if any), then refreshes from TorBox.
  Future<void> load() async {
    final snap = AppSettings.librarySnapshot;
    if (snap != null && isEmpty) {
      try {
        final files = (jsonDecode(snap) as List)
            .map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
            .toList();
        await _build(files, quiet: true);
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

  Future<void> _build(List<MediaFile> files, {bool quiet = false}) async {
    // Group files by parsed title so each title is looked up once.
    final movieGroups = <String, _Group>{};
    final showGroups = <String, _Group>{};
    for (final f in files) {
      final p = NameParser.parseFile(f.fileName, f.fullPath, f.itemName);
      if (p.title.isEmpty) {
        movieGroups.putIfAbsent('?${f.key}', () => _Group('', null)).files.add(_PF(f, p));
        continue;
      }
      final norm = NameParser.normalize(p.title);
      if (p.isEpisode) {
        showGroups.putIfAbsent(norm, () => _Group(p.title, p.year)).files.add(_PF(f, p));
      } else {
        movieGroups
            .putIfAbsent('$norm|${p.year ?? ''}', () => _Group(p.title, p.year))
            .files
            .add(_PF(f, p));
      }
    }

    final total = movieGroups.length + showGroups.length;
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
    final unmatched = <MediaFile>[];

    final tasks = <Future<void> Function()>[];
    for (final g in movieGroups.values) {
      tasks.add(() async {
        TmdbInfo? info;
        if (g.title.isNotEmpty) {
          try {
            info = await TmdbApi.findMovie(g.title, g.year);
          } catch (_) {}
        }
        if (info == null) {
          unmatched.addAll(g.files.map((e) => e.file));
        } else {
          final m = movieMap.putIfAbsent(info.id, () => Movie(info!));
          m.files.addAll(g.files.map((e) => e.file));
        }
        tick();
      });
    }
    for (final g in showGroups.values) {
      tasks.add(() async {
        TmdbInfo? info;
        try {
          info = await TmdbApi.findShow(g.title, g.year);
        } catch (_) {}
        if (info == null) {
          unmatched.addAll(g.files.map((e) => e.file));
        } else {
          final s = showMap.putIfAbsent(info.id, () => Show(info!));
          for (final pf in g.files) {
            s.episodes.add(EpisodeFile(pf.parsed.season!, pf.parsed.episode!, pf.file));
          }
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
    others = unmatched..sort((a, b) => b.added.compareTo(a.added));
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

  /// Rebuilds after clearing TMDB matches (e.g. after changing language).
  Future<void> rematch() async {
    await AppSettings.clearMatchCache();
    movies = [];
    shows = [];
    others = [];
    await refresh();
  }
}

class _PF {
  final MediaFile file;
  final ParsedName parsed;
  _PF(this.file, this.parsed);
}

class _Group {
  final String title;
  final int? year;
  final List<_PF> files = [];
  _Group(this.title, this.year);
}
