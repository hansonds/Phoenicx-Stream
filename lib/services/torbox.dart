import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'settings.dart';

class TorBoxException implements Exception {
  final String message;
  TorBoxException(this.message);
  @override
  String toString() => message;
}

/// Talks directly to api.torbox.app from the device.
class TorBoxApi {
  static const _base = 'https://api.torbox.app/v1/api';
  static const videoExt = {
    'mkv', 'mp4', 'avi', 'm4v', 'mov', 'wmv', 'ts', 'm2ts', 'webm', 'mpg', 'mpeg', 'flv', 'vob'
  };

  static Map<String, String> _headers(String key) => {
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
      };

  /// Checks the key; returns the account email/plan text on success.
  static Future<String> testKey(String key) async {
    final r = await http
        .get(Uri.parse('$_base/user/me'), headers: _headers(key))
        .timeout(const Duration(seconds: 20));
    final body = _decode(r);
    final data = body['data'];
    if (data is Map) {
      final email = data['email'] ?? '';
      return 'Connected${email.toString().isNotEmpty ? ' as $email' : ''}';
    }
    return 'Connected';
  }

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw TorBoxException('TorBox returned HTTP ${r.statusCode}');
    }
    if (r.statusCode >= 400 || body['success'] == false) {
      final detail = body['detail'] ?? body['error'] ?? 'HTTP ${r.statusCode}';
      throw TorBoxException('TorBox: $detail');
    }
    return body;
  }

  static bool _isVideo(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return videoExt.contains(name.substring(dot + 1).toLowerCase());
  }

  /// All finished video files from torrents, usenet and web downloads.
  static Future<List<MediaFile>> fetchAllVideoFiles() async {
    final key = AppSettings.torboxKey;
    if (key.isEmpty) throw TorBoxException('Add your TorBox API key in Settings');
    Future<List<MediaFile>> safe(SourceType t) async {
      try {
        return await _fetchType(key, t);
      } catch (e) {
        // A failing type (e.g. usenet not on the plan) should not break the rest,
        // unless it's the torrents list.
        if (t == SourceType.torrent) rethrow;
        return <MediaFile>[];
      }
    }

    final results = await Future.wait(SourceType.values.map(safe));
    return results.expand((e) => e).toList();
  }

  static Future<List<MediaFile>> _fetchType(String key, SourceType type) async {
    final out = <MediaFile>[];
    const limit = 1000;
    var offset = 0;
    while (true) {
      final uri = Uri.parse('$_base/${type.path}/mylist').replace(queryParameters: {
        'bypass_cache': 'true',
        'offset': '$offset',
        'limit': '$limit',
      });
      final r = await http.get(uri, headers: _headers(key)).timeout(const Duration(seconds: 40));
      final body = _decode(r);
      final data = body['data'];
      final items = data is List ? data : (data is Map ? [data] : const []);
      for (final it in items) {
        if (it is! Map) continue;
        final ready = it['download_present'] == true ||
            it['download_finished'] == true ||
            it['cached'] == true;
        if (!ready) continue;
        final itemId = (it['id'] as num?)?.toInt();
        if (itemId == null) continue;
        final itemName = (it['name'] ?? '').toString();
        final added = DateTime.tryParse((it['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final files = it['files'];
        if (files is! List) continue;
        for (final f in files) {
          if (f is! Map) continue;
          final full = (f['name'] ?? '').toString();
          final short = (f['short_name'] ?? full.split('/').last).toString();
          final size = (f['size'] as num?)?.toInt() ?? 0;
          final mime = (f['mimetype'] ?? '').toString();
          if (!(_isVideo(short) || mime.startsWith('video/'))) continue;
          // Skip samples and tiny extras.
          if (RegExp(r'(^|[ ._\-\[(])sample([ ._\-\])]|$)', caseSensitive: false).hasMatch(short) &&
              size < 400 * 1024 * 1024) {
            continue;
          }
          if (size > 0 && size < 40 * 1024 * 1024) continue;
          final fileId = (f['id'] as num?)?.toInt();
          if (fileId == null) continue;
          out.add(MediaFile(
            source: type,
            itemId: itemId,
            fileId: fileId,
            fileName: short,
            fullPath: full,
            itemName: itemName,
            size: size,
            added: added,
          ));
        }
      }
      if (items.length < limit) break;
      offset += limit;
    }
    return out;
  }

  /// Gets a direct stream link for one file. Retries because TorBox sometimes
  /// answers 500 on the first try.
  static Future<String> streamLink(MediaFile file) async {
    final key = AppSettings.torboxKey;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = Uri.parse('$_base/${file.source.path}/requestdl').replace(queryParameters: {
          'token': key,
          file.source.idParam: '${file.itemId}',
          'file_id': '${file.fileId}',
          'zip_link': 'false',
          'redirect': 'false',
        });
        final r = await http.get(uri, headers: _headers(key)).timeout(const Duration(seconds: 30));
        final body = _decode(r);
        final data = body['data'];
        if (data is String && data.startsWith('http')) return data;
        throw TorBoxException('TorBox did not return a link');
      } catch (e) {
        lastError = e;
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }
    throw lastError is TorBoxException ? lastError : TorBoxException('Could not get link: $lastError');
  }
}
