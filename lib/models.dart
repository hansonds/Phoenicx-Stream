/// Data models used across the app.

/// The three kinds of downloads TorBox keeps.
enum SourceType { torrent, usenet, webdl }

extension SourceTypeApi on SourceType {
  /// Path segment used by the TorBox API.
  String get path {
    switch (this) {
      case SourceType.torrent:
        return 'torrents';
      case SourceType.usenet:
        return 'usenet';
      case SourceType.webdl:
        return 'webdl';
    }
  }

  /// Query parameter name for the item id in requestdl.
  String get idParam {
    switch (this) {
      case SourceType.torrent:
        return 'torrent_id';
      case SourceType.usenet:
        return 'usenet_id';
      case SourceType.webdl:
        return 'web_id';
    }
  }
}

SourceType sourceTypeFromName(String n) =>
    SourceType.values.firstWhere((e) => e.name == n, orElse: () => SourceType.torrent);

/// One playable video file inside the TorBox account.
class MediaFile {
  final SourceType source;
  final int itemId;
  final int fileId;
  final String fileName; // just the file name
  final String fullPath; // path inside the download, may include folders
  final String itemName; // torrent / usenet / webdl name
  final int size;
  final DateTime added;

  MediaFile({
    required this.source,
    required this.itemId,
    required this.fileId,
    required this.fileName,
    required this.fullPath,
    required this.itemName,
    required this.size,
    required this.added,
  });

  String get key => '${source.name}:$itemId:$fileId';

  Map<String, dynamic> toJson() => {
        's': source.name,
        'i': itemId,
        'f': fileId,
        'n': fileName,
        'p': fullPath,
        'in': itemName,
        'z': size,
        'a': added.millisecondsSinceEpoch,
      };

  factory MediaFile.fromJson(Map<String, dynamic> j) => MediaFile(
        source: sourceTypeFromName(j['s'] as String),
        itemId: j['i'] as int,
        fileId: j['f'] as int,
        fileName: j['n'] as String,
        fullPath: (j['p'] ?? j['n']) as String,
        itemName: (j['in'] ?? '') as String,
        size: (j['z'] ?? 0) as int,
        added: DateTime.fromMillisecondsSinceEpoch((j['a'] ?? 0) as int),
      );
}

/// Basic TMDB info for a movie or a show.
class TmdbInfo {
  final int id;
  final String title;
  final int? year;
  final String? poster;
  final String? backdrop;
  final String overview;
  final double rating;

  TmdbInfo({
    required this.id,
    required this.title,
    this.year,
    this.poster,
    this.backdrop,
    this.overview = '',
    this.rating = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'year': year,
        'poster': poster,
        'backdrop': backdrop,
        'overview': overview,
        'rating': rating,
      };

  factory TmdbInfo.fromJson(Map<String, dynamic> j) => TmdbInfo(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        year: j['year'] as int?,
        poster: j['poster'] as String?,
        backdrop: j['backdrop'] as String?,
        overview: (j['overview'] ?? '') as String,
        rating: ((j['rating'] ?? 0) as num).toDouble(),
      );
}

/// A movie in the library (one TMDB movie, possibly several file versions).
class Movie {
  final TmdbInfo info;
  final List<MediaFile> files = [];
  Movie(this.info);

  DateTime get added =>
      files.map((f) => f.added).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// One episode file of a show.
class EpisodeFile {
  final int season;
  final int episode;
  final MediaFile file;
  EpisodeFile(this.season, this.episode, this.file);
}

/// A TV show in the library.
class Show {
  final TmdbInfo info;
  final List<EpisodeFile> episodes = [];
  Show(this.info);

  DateTime get added => episodes
      .map((e) => e.file.added)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  List<int> get seasons {
    final s = episodes.map((e) => e.season).toSet().toList()..sort();
    return s;
  }

  /// Episodes of a season grouped by episode number (several versions possible).
  Map<int, List<EpisodeFile>> episodesOf(int season) {
    final map = <int, List<EpisodeFile>>{};
    for (final e in episodes.where((e) => e.season == season)) {
      map.putIfAbsent(e.episode, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }
}

/// One episode from TMDB season details.
class TmdbEpisode {
  final int number;
  final String name;
  final String overview;
  final String? still;
  TmdbEpisode(this.number, this.name, this.overview, this.still);
}

/// What the player needs to play something.
class PlayItem {
  final MediaFile file;
  final String title;
  final String subtitle;
  final String? image;
  PlayItem({required this.file, required this.title, this.subtitle = '', this.image});
}
