import 'package:flutter/material.dart';

import '../services/library.dart';
import '../services/settings.dart';
import '../services/tmdb.dart';
import '../services/torbox.dart';
import 'theme.dart';
import 'widgets.dart';

/// API keys and app options. Shown first when keys are missing.
class SettingsScreen extends StatefulWidget {
  final bool firstRun;
  final VoidCallback? onDone;
  const SettingsScreen({super.key, this.firstRun = false, this.onDone});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _torbox = TextEditingController(text: AppSettings.torboxKey);
  late final _tmdb = TextEditingController(text: AppSettings.tmdbKey);
  late final _lang = TextEditingController(text: AppSettings.language);
  bool _hide = true;
  bool _saving = false;
  String? _torboxStatus;
  String? _tmdbStatus;
  bool _torboxOk = false;
  bool _tmdbOk = false;

  @override
  void dispose() {
    _torbox.dispose();
    _tmdb.dispose();
    _lang.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _torboxStatus = 'Checking…';
      _tmdbStatus = 'Checking…';
    });
    final tk = _torbox.text.trim();
    final mk = _tmdb.text.trim();
    final results = await Future.wait([
      TorBoxApi.testKey(tk).then((v) => v).catchError((e) => 'ERR:$e'),
      TmdbApi.testKey(mk).then((v) => v).catchError((e) => 'ERR:$e'),
    ]);
    _torboxOk = !results[0].startsWith('ERR:');
    _tmdbOk = !results[1].startsWith('ERR:');
    setState(() {
      _torboxStatus = _torboxOk ? results[0] : results[0].substring(4);
      _tmdbStatus = _tmdbOk ? results[1] : results[1].substring(4);
      _saving = false;
    });
    if (_torboxOk && _tmdbOk) {
      final langChanged = _lang.text.trim().isNotEmpty && _lang.text.trim() != AppSettings.language;
      final tmdbChanged = mk != AppSettings.tmdbKey;
      AppSettings.torboxKey = tk;
      AppSettings.tmdbKey = mk;
      if (_lang.text.trim().isNotEmpty) AppSettings.language = _lang.text.trim();
      if (widget.firstRun) {
        widget.onDone?.call();
      } else {
        if (langChanged || tmdbChanged) {
          Library.instance.rematch();
        } else {
          Library.instance.refresh();
        }
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  Widget _status(String? text, bool ok) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : (text == 'Checking…' ? Icons.hourglass_top : Icons.error),
              size: 16, color: ok ? Colors.greenAccent : (text == 'Checking…' ? PX.muted : PX.accent)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(color: PX.muted, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _field(String label, String hint, TextEditingController c, {bool secret = true}) {
    return TextField(
      controller: c,
      obscureText: secret && _hide,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = Layout.pad(context);
    return Scaffold(
      appBar: widget.firstRun
          ? null
          : AppBar(title: const Text('Settings'), backgroundColor: PX.bg),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.all(pad),
              children: [
                if (widget.firstRun) ...[
                  const SizedBox(height: 20),
                  Center(child: Image.asset('assets/logo.png', width: 96, height: 96)),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text('Phoenicx Stream',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('Your TorBox library, arranged by TMDB',
                        style: TextStyle(color: PX.muted)),
                  ),
                  const SizedBox(height: 28),
                ],
                const Text('TorBox', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('torbox.app → Settings → API Key',
                    style: TextStyle(color: PX.muted, fontSize: 13)),
                const SizedBox(height: 10),
                _field('TorBox API key', 'Paste your TorBox API key', _torbox),
                _status(_torboxStatus, _torboxOk),
                const SizedBox(height: 24),
                const Text('TMDB', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'themoviedb.org → Settings → API. Either the "API Key" or the "API Read Access Token" works.',
                    style: TextStyle(color: PX.muted, fontSize: 13)),
                const SizedBox(height: 10),
                _field('TMDB API key or Read Access Token', 'Paste your TMDB key', _tmdb),
                _status(_tmdbStatus, _tmdbOk),
                const SizedBox(height: 16),
                _field('TMDB language (e.g. en-US, ml-IN, ta-IN)', 'en-US', _lang, secret: false),
                const SizedBox(height: 12),
                Row(
                  children: [
                    PillButton(
                      label: _hide ? 'Show keys' : 'Hide keys',
                      icon: _hide ? Icons.visibility : Icons.visibility_off,
                      onTap: () => setState(() => _hide = !_hide),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    PillButton(
                      label: _saving ? 'Checking…' : 'Save & connect',
                      icon: Icons.link,
                      primary: true,
                      onTap: _saving ? () {} : _save,
                    ),
                  ],
                ),
                if (!widget.firstRun) ...[
                  const SizedBox(height: 36),
                  const Divider(color: PX.surface2),
                  const SizedBox(height: 12),
                  const Text('Library', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      PillButton(
                        label: 'Re-match all titles',
                        icon: Icons.auto_fix_high,
                        onTap: () {
                          Library.instance.rematch();
                          Navigator.of(context).pop();
                        },
                      ),
                      PillButton(
                        label: 'Clear watch history',
                        icon: Icons.history,
                        onTap: () async {
                          await AppSettings.clearProgress();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Watch history cleared')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Phoenicx Stream v1.0 • by Hanson\nEverything runs on this device. Keys are stored only here. '
                    'This product uses the TMDB API but is not endorsed or certified by TMDB.',
                    style: TextStyle(color: PX.muted, fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
