import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores API keys, TMDB match cache and watch progress on the device.
class AppSettings {
  AppSettings._();
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static String get torboxKey => _p.getString('torbox_key') ?? '';
  static set torboxKey(String v) => _p.setString('torbox_key', v.trim());

  static String get tmdbKey => _p.getString('tmdb_key') ?? '';
  static set tmdbKey(String v) => _p.setString('tmdb_key', v.trim());

  /// TMDB language, e.g. en-US.
  static String get language => _p.getString('tmdb_lang') ?? 'en-US';
  static set language(String v) => _p.setString('tmdb_lang', v.trim());

  static bool get hasKeys => torboxKey.isNotEmpty && tmdbKey.isNotEmpty;

  // ---------- TMDB match cache ----------
  static Map<String, dynamic>? _matchCache;

  static Map<String, dynamic> get matchCache {
    if (_matchCache != null) return _matchCache!;
    try {
      _matchCache = jsonDecode(_p.getString('tmdb_cache') ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      _matchCache = {};
    }
    return _matchCache!;
  }

  static Future<void> saveMatchCache() async {
    await _p.setString('tmdb_cache', jsonEncode(matchCache));
  }

  static Future<void> clearMatchCache() async {
    _matchCache = {};
    await _p.remove('tmdb_cache');
  }

  // ---------- Watch progress ----------
  static Map<String, dynamic>? _progress;

  static Map<String, dynamic> get progress {
    if (_progress != null) return _progress!;
    try {
      _progress = jsonDecode(_p.getString('progress') ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      _progress = {};
    }
    return _progress!;
  }

  /// Saved position for a file, or null.
  static Duration? positionOf(String fileKey) {
    final e = progress[fileKey];
    if (e is Map && e['pos'] is int) return Duration(milliseconds: e['pos'] as int);
    return null;
  }

  static Future<void> saveProgress(String fileKey, Map<String, dynamic> entry) async {
    progress[fileKey] = entry;
    await _p.setString('progress', jsonEncode(progress));
  }

  static Future<void> removeProgress(String fileKey) async {
    progress.remove(fileKey);
    await _p.setString('progress', jsonEncode(progress));
  }

  static Future<void> clearProgress() async {
    _progress = {};
    await _p.remove('progress');
  }

  // ---------- Last library snapshot (for fast start) ----------
  static String? get librarySnapshot => _p.getString('library_files');
  static Future<void> saveLibrarySnapshot(String json) => _p.setString('library_files', json);
}
