/// Turns messy release file names into a title / year / season / episode.
class ParsedName {
  final String title;
  final int? year;
  final int? season;
  final int? episode;
  ParsedName(this.title, {this.year, this.season, this.episode});

  bool get isEpisode => season != null && episode != null;

  @override
  String toString() => 'ParsedName($title, y:$year, s:$season, e:$episode)';
}

class NameParser {
  static final _ext = RegExp(r'\.[A-Za-z0-9]{2,4}$');
  static final _sitePrefix = RegExp(r'^\s*(www\.)?[A-Za-z0-9\-]+\.(com|org|net|in|ws|xyz|cc|me|to|se|li|pw|lol|fans|io|co|ms|bz|ink|day|life|fyi|win|vip|art)\s*[-–_]+\s*', caseSensitive: false);
  static final _groupPrefix = RegExp(r'^\s*[\[【][^\]】]*[\]】]\s*');

  static final _epPatterns = <RegExp>[
    RegExp(r'(?<![A-Za-z0-9])[Ss](\d{1,2})[ ._\-]?[Ee][Pp]?(\d{1,3})(?!\d)'),
    RegExp(r'(?<![A-Za-z0-9])(\d{1,2})x(\d{2,3})(?!\d)'),
    RegExp(r'Season[ ._\-]?(\d{1,2})[ ._\-]*Episode[ ._\-]?(\d{1,3})', caseSensitive: false),
  ];
  static final _seasonOnly = <RegExp>[
    RegExp(r'(?<![A-Za-z0-9])[Ss](\d{1,2})(?![0-9])'),
    RegExp(r'Season[ ._\-]?(\d{1,2})', caseSensitive: false),
  ];
  static final _episodeOnly = <RegExp>[
    RegExp(r'(?<![A-Za-z0-9])[Ee][Pp]?(\d{1,3})(?!\d)'),
    RegExp(r'Episode[ ._\-]?(\d{1,3})', caseSensitive: false),
    RegExp(r'^\s*(\d{1,3})(?!\d)'),
  ];
  static final _year = RegExp(r'(?<![0-9])(19[2-9]\d|20[0-4]\d)(?![0-9])');
  static final _junk = RegExp(
      r'(?<![A-Za-z0-9])(2160p|1080p|1080i|720p|576p|480p|4k|uhd|web[ ._\-]?dl|web[ ._\-]?rip|bluray|blu[ ._\-]ray|brrip|bdrip|bd[ ._\-]?rip|hdrip|dvdrip|dvdscr|hdtv|hdcam|camrip|predvd|x264|x265|h[ ._]?264|h[ ._]?265|hevc|remux|proper|repack|extended|unrated|directors[ ._]cut|imax|hdr10|hdr|dovi|10bit|8bit|amzn|dsnp|hmax|atvp|zee5|jhs|ddp?\d?[ ._]?\d?|aac|dts|truehd|atmos|esub|esubs|dual[ ._\-]audio|uncut|tamil|telugu|hindi|malayalam|kannada|eng)(?![A-Za-z0-9])',
      caseSensitive: false);

  static String _stripExt(String n) => n.replaceFirst(_ext, '');

  static String _clean(String s) {
    var t = s;
    // Cut at the first quality / junk token.
    final j = _junk.firstMatch(t);
    if (j != null && j.start > 0) t = t.substring(0, j.start);
    t = t.replaceAll(RegExp(r'[._]'), ' ');
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'\(\s*\)'), ' ');
    t = t.replaceAll(RegExp(r'[\(\[\{]+\s*$'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^[\-–:\s]+|[\-–:\s]+$'), '');
    return t.trim();
  }

  static String _prep(String name) {
    var n = _stripExt(name.trim());
    for (var i = 0; i < 3; i++) {
      final before = n;
      n = n.replaceFirst(_sitePrefix, '').replaceFirst(_groupPrefix, '');
      if (n == before) break;
    }
    return n;
  }

  /// Parses a single name (file name or folder name).
  static ParsedName parse(String raw) {
    final name = _prep(raw);

    for (final p in _epPatterns) {
      final m = p.firstMatch(name);
      if (m != null) {
        final title = _clean(name.substring(0, m.start));
        final ym = _year.firstMatch(name.substring(0, m.start));
        var t = title;
        if (ym != null && ym.start > 0) {
          t = _clean(name.substring(0, ym.start));
        }
        return ParsedName(t,
            year: ym != null ? int.parse(ym.group(1)!) : null,
            season: int.parse(m.group(1)!),
            episode: int.parse(m.group(2)!));
      }
    }

    // Movie: title before the year.
    for (final ym in _year.allMatches(name)) {
      if (ym.start == 0) continue;
      final title = _clean(name.substring(0, ym.start));
      if (title.isEmpty) continue;
      return ParsedName(title, year: int.parse(ym.group(1)!));
    }
    return ParsedName(_clean(name));
  }

  /// Parses a file using its own name first, then the folders and the
  /// download name to fill in missing title / season / episode.
  static ParsedName parseFile(String fileName, String fullPath, String itemName) {
    final f = parse(fileName);
    if (f.isEpisode && f.title.length >= 2) return f;

    // Collect context names: folders (closest first) then the item name.
    final parts = fullPath.split('/');
    final folders = parts.length > 1 ? parts.sublist(0, parts.length - 1).reversed.toList() : <String>[];
    final contexts = [...folders, itemName].where((s) => s.trim().isNotEmpty).toList();

    if (f.isEpisode) {
      // Episode but no usable title in the file name.
      for (final c in contexts) {
        final p = parse(c);
        if (p.title.length >= 2 && !_isSeasonWord(p.title)) {
          return ParsedName(p.title, year: p.year ?? f.year, season: f.season, episode: f.episode);
        }
      }
      return f;
    }

    // No SxxEyy in the file name: maybe the folder says the season and the
    // file only has the episode number.
    int? season;
    String? showTitle;
    int? showYear;
    for (final c in contexts) {
      final prepped = _prep(c);
      for (final sp in _seasonOnly) {
        final m = sp.firstMatch(prepped);
        if (m != null) {
          season ??= int.parse(m.group(1)!);
          final t = _clean(prepped.substring(0, m.start));
          if (t.length >= 2 && showTitle == null) {
            showTitle = t;
            final ym = _year.firstMatch(prepped.substring(0, m.start));
            if (ym != null && ym.start > 0) {
              showTitle = _clean(prepped.substring(0, ym.start));
              showYear = int.parse(ym.group(1)!);
            }
          }
          break;
        }
      }
      if (season != null && showTitle != null) break;
    }
    if (season != null) {
      final fn = _prep(fileName);
      for (final ep in _episodeOnly) {
        final m = ep.firstMatch(fn);
        if (m != null) {
          final e = int.parse(m.group(1)!);
          if (e > 0 && e < 400) {
            String? title = showTitle;
            if (title == null) {
              for (final c in contexts) {
                final p = parse(c);
                if (p.title.length >= 2 && !_isSeasonWord(p.title)) {
                  title = p.title;
                  break;
                }
              }
            }
            if (title != null) {
              return ParsedName(title, year: showYear, season: season, episode: e);
            }
          }
        }
      }
    }

    // Movie. If the file name is weak (no year, very short), try the item name.
    if (f.year == null || f.title.length < 2) {
      for (final c in contexts) {
        final p = parse(c);
        if (p.year != null && p.title.length >= 2 && !p.isEpisode) return p;
      }
    }
    return f;
  }

  static bool _isSeasonWord(String t) =>
      RegExp(r'^(season|s)\s*\d*$', caseSensitive: false).hasMatch(t.trim());

  /// Key used to group files that belong to the same title.
  static String normalize(String t) =>
      t.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');
}
