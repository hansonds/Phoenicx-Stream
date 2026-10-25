import 'package:flutter/material.dart';

class PX {
  static const bg = Color(0xFF09090D);
  static const surface = Color(0xFF15151C);
  static const surface2 = Color(0xFF1E1E28);
  static const accent = Color(0xFFFF6A2B);
  static const accent2 = Color(0xFFFFB347);
  static const text = Color(0xFFF4F1EC);
  static const muted = Color(0xFF9C98A6);

  static const fire = LinearGradient(
    colors: [Color(0xFFFF3D2E), accent, accent2],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        primary: accent,
      ),
      scaffoldBackgroundColor: bg,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
      focusColor: accent.withOpacity(0.25),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      ),
    );
  }
}

/// Screen size helpers so the same UI works on phone, TV and Windows.
class Layout {
  static bool wide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
  static double posterWidth(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    if (w < 500) return 112;
    if (w < 900) return 140;
    if (w < 1500) return 160;
    return 190;
  }

  static double pad(BuildContext c) => wide(c) ? 40 : 16;
}

String formatSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i < 2 ? 0 : 1)} ${units[i]}';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
