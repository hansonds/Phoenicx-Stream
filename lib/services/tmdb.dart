import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'settings.dart';

class TmdbException implements Exception {
  final String message;
  TmdbException(this.message);
  @override
  String toString() => message;
}

/// TMDB lookups, directly from the device. Accepts either the v3 "API Key"
/// or the v4 "API Read Access Token".
class TmdbApi {
  static const _base = 'https://api.themoviedb.org/3';
  static const img = 'https://image.tmdb.org/t/p';

  static String? poster(String? path, {String size = 'w342'}) =>
      path == null || path.isEmpty ? null : '$img/$size$path';
  static String? backdrop(String? path, {String size = 'w1280'}) =>
      path == null || path.isEmpty ? null : '$img/$size$path';

  static bool _isToken(String key) => key.startsWith('eyJ') || key.length > 60;

  static Future<Map<String, dynamic>> _get(String path, Map<String, String> params,
      {String? key}) async {
    final k = key ?? AppSettings.tmdbKey;
    if (k.isEmpty) throw TmdbException('Add your TMDB key in Settings');
    final q = {...params, 'language': AppSettings.language};
    final headers = {'Accept': 'application/json'};
    if (_isToken(k)) {
      headers['Authorization'] = 'Bearer $k';
    } else {
      q['api_key'] = k;
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: q);
    http.Response r;
    var tries = 0;
    while (true) {
      r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (r.statusCode == 429 && tries < 4) {
        tries++;
        await Future.delayed(Duration(seconds: tries));
        continue;
      }
      break;
    }
    if (r.statusCode == 401) throw TmdbException('TMDB key was rejected');
    if (r.statusCode >= 400) throw TmdbException('TMDB error ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<String> testKey(String key) async {
    await _get('/configuration', {}, key: key);
    return 'Connected';
  }

  static int? _yearOf(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  static TmdbInfo _movieInfo(Map m) => TmdbInfo(
        id: m['id'] as int,
        title: (m['title'] ?? m['original_title'] ?? '').toString(),
        year: _yearOf(m['release_date'] as String?),
        poster: m['poster_path'] as String?,
        backdrop: m['backdrop_path'] as String?,
        overview: (m['overview'] ?? '').toString(),
        rating: ((m['vote_average'] ?? 0) as num).toDouble(),
      );

  static TmdbInfo _tvInfo(Map m) => TmdbInfo(
        id: m['id'] as int,
        title: (m['name'] ?? m['original_name'] ?? '').toString(),
        year: _yearOf(m['first_air_date'] as String?),
        poster: m['poster_path'] as String?,
        backdrop: m['backdrop_path'] as String?,
        overview: (m['overview'] ?? '').toString(),
        rating: ((m['vote_average'] ?? 0) as num).toDouble(),
      );

  /// Finds a movie, using the cache first. Returns null when nothing matches.
  static Future<TmdbInfo?> findMovie(String title, int? year) async {
    final ck = 'm|${title.toLowerCase()}|${year ?? ''}';
    final cache = AppSettings.matchCache;
    if (cache.containsKey(ck)) {
      final v = cache[ck];
      return v is Map<String, dynamic> ? TmdbInfo.fromJson(v) : null;
    }
    TmdbInfo? found;
    var res = await _get('/search/movie', {
      'query': title,
      if (year != null) 'year': '$year',
      'include_adult': 'false',
    });
    var list = (res['results'] as List?) ?? const [];
    if (list.isEmpty && year != null) {
      // Release year in names is sometimes off by one.
      res = await _get('/search/movie', {'query': title, 'include_adult': 'false'});
      list = (res['results'] as List?) ?? const [];
      list = list.where((m) {
        final y = _yearOf((m as Map)['release_date'] as String?);
        return y == null || (y - year).abs() <= 1;
      }).toList();
    }
    if (list.isNotEmpty) found = _movieInfo(list.first as Map);
    cache[ck] = found?.toJson();
    return found;
  }

  /// Finds a TV show, using the cache first.
  static Future<TmdbInfo?> findShow(String title, int? year) async {
    final ck = 't|${title.toLowerCase()}|${year ?? ''}';
    final cache = AppSettings.matchCache;
    if (cache.containsKey(ck)) {
      final v = cache[ck];
      return v is Map<String, dynamic> ? TmdbInfo.fromJson(v) : null;
    }
    TmdbInfo? found;
    var res = await _get('/search/tv', {
      'query': title,
      if (year != null) 'first_air_date_year': '$year',
      'include_adult': 'false',
    });
    var list = (res['results'] as List?) ?? const [];
    if (list.isEmpty && year != null) {
      res = await _get('/search/tv', {'query': title, 'include_adult': 'false'});
      list = (res['results'] as List?) ?? const [];
    }
    if (list.isNotEmpty) found = _tvInfo(list.first as Map);
    cache[ck] = found?.toJson();
    return found;
  }

  static final Map<String, List<TmdbEpisode>> _seasonCache = {};

  /// Episode names, overviews and stills for one season.
  static Future<List<TmdbEpisode>> season(int showId, int season) async {
    final k = '$showId/$season';
    final c = _seasonCache[k];
    if (c != null) return c;
    final res = await _get('/tv/$showId/season/$season', {});
    final eps = ((res['episodes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => TmdbEpisode(
              (e['episode_number'] as num?)?.toInt() ?? 0,
              (e['name'] ?? '').toString(),
              (e['overview'] ?? '').toString(),
              e['still_path'] as String?,
            ))
        .toList();
    _seasonCache[k] = eps;
    return eps;
  }
}
