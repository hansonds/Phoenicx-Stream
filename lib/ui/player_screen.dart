import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../services/settings.dart';
import '../services/torbox.dart';
import 'theme.dart';

/// Full-screen player. Works with touch, mouse/keyboard and TV remote.
class PlayerScreen extends StatefulWidget {
  final List<PlayItem> playlist;
  final int index;
  final bool resume;

  const PlayerScreen({super.key, required this.playlist, this.index = 0, this.resume = true});

  static Future<void> open(BuildContext context, List<PlayItem> playlist,
      {int index = 0, bool resume = true}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(playlist: playlist, index: index, resume: resume),
    ));
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Phoenicx Stream',
      bufferSize: 64 * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(_player);

  late int _index = widget.index;
  PlayItem get _item => widget.playlist[_index];

  final _rootFocus = FocusNode(debugLabel: 'player-root');
  final _playFocus = FocusNode(debugLabel: 'play-button');

  bool _loading = true;
  String? _error;
  bool _controls = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  Timer? _saveTimer;
  String? _toast;
  Timer? _toastTimer;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  final List<StreamSubscription> _subs = [];

  static bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _player.stream.position.listen((p) => setState(() => _pos = p)),
      _player.stream.duration.listen((d) => setState(() => _dur = d)),
      _player.stream.playing.listen((p) {
        setState(() => _playing = p);
        if (p) _scheduleHide();
      }),
      _player.stream.buffering.listen((b) => setState(() => _buffering = b)),
      _player.stream.completed.listen((c) {
        if (c) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        if (_pos == Duration.zero && mounted) setState(() => _error = e);
      }),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    if (!_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _start(resume: widget.resume);
  }

  Future<void> _start({required bool resume}) async {
    setState(() {
      _loading = true;
      _error = null;
      _pos = Duration.zero;
      _dur = Duration.zero;
    });
    try {
      final url = await TorBoxApi.streamLink(_item.file);
      final platform = _player.platform;
      if (platform != null) {
        // Generous network cache for big remuxes over the internet.
        for (final e in {
          'cache': 'yes',
          'demuxer-max-bytes': '200MiB',
          'demuxer-max-back-bytes': '50MiB',
          'demuxer-readahead-secs': '60',
          'network-timeout': '60',
          'sub-auto': 'fuzzy',
        }.entries) {
          try {
            await (platform as dynamic).setProperty(e.key, e.value);
          } catch (_) {}
        }
      }
      await _player.open(Media(url));
      final saved = AppSettings.positionOf(_item.file.key);
      if (resume && saved != null && saved > const Duration(seconds: 30)) {
        try {
          if (_player.state.duration <= Duration.zero) {
            await _player.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(const Duration(seconds: 30));
          }
          await _player.seek(saved);
        } catch (_) {}
      }
      if (mounted) setState(() => _loading = false);
      _showControls();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onCompleted() {
    _finished();
    if (_index + 1 < widget.playlist.length) {
      _index++;
      _flash('Next: ${_item.title} ${_item.subtitle}');
      _start(resume: true);
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _finished() async {
    await AppSettings.removeProgress(_item.file.key);
  }

  Future<void> _saveProgress() async {
    if (_dur <= Duration.zero || _pos < const Duration(seconds: 20)) return;
    if (_pos.inMilliseconds > _dur.inMilliseconds * 0.94) {
      await _finished();
      return;
    }
    await AppSettings.saveProgress(_item.file.key, {
      'pos': _pos.inMilliseconds,
      'dur': _dur.inMilliseconds,
      't': DateTime.now().millisecondsSinceEpoch,
      'title': _item.title,
      'subtitle': _item.subtitle,
      'image': _item.image,
      'file': _item.file.toJson(),
    });
  }

  // ---------- controls visibility ----------
  void _showControls({bool focusPlay = false}) {
    if (!mounted) return;
    setState(() => _controls = true);
    if (focusPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && _error == null) {
        setState(() => _controls = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() => _controls = false);
    _rootFocus.requestFocus();
  }

  void _flash(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---------- actions ----------
  void _togglePlay() {
    _player.playOrPause();
    _showControls();
  }

  void _seekBy(int seconds) {
    var t = _pos + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (_dur > Duration.zero && t > _dur) t = _dur - const Duration(seconds: 1);
    _player.seek(t);
    _flash('${seconds > 0 ? '+' : ''}${seconds}s  •  ${formatDuration(t)}');
  }

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    setState(() {});
  }

  Future<void> _exit() async {
    await _saveProgress();
    if (_fullscreen) {
      await windowManager.setFullScreen(false);
      _fullscreen = false;
    }
    if (mounted) Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;

    // Media keys work any time.
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      if (e is KeyDownEvent) _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _player.play();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      _player.pause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        _toggleFullscreen();
      } else if (_controls && !_isDesktop) {
        _hideControls();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF && _isDesktop) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    if (!_controls) {
      // Controls hidden: remote shortcuts.
      if (k == LogicalKeyboardKey.arrowLeft) {
        _seekBy(-10);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _seekBy(30);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        _showControls(focusPlay: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Controls visible: keep them alive while the user navigates.
    _scheduleHide();
    if (_rootFocus.hasPrimaryFocus && _error == null) {
      // Nothing focused yet: first key press lands on the play button.
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        _playFocus.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---------- tracks ----------
  String _trackLabel(String id, String? title, String? lang, int i) {
    final parts = <String>[];
    if (title != null && title.isNotEmpty) parts.add(title);
    if (lang != null && lang.isNotEmpty) parts.add(lang.toUpperCase());
    return parts.isEmpty ? 'Track ${i + 1}' : parts.join('  •  ');
  }

  Future<void> _pickAudio() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final current = _player.state.track.audio;
    await _pickFrom(
      'Audio',
      [
        for (var i = 0; i < tracks.length; i++)
          _Choice(_trackLabel(tracks[i].id, tracks[i].title, tracks[i].language, i),
              tracks[i].id == current.id, () => _player.setAudioTrack(tracks[i])),
      ],
    );
    _scheduleHide();
  }

  Future<void> _pickSubtitle() async {
    _hideTimer?.cancel();
    final tracks =
        _player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final current = _player.state.track.subtitle;
    await _pickFrom(
      'Subtitles',
      [
        _Choice('Off', current.id == 'no', () => _player.setSubtitleTrack(SubtitleTrack.no())),
        for (var i = 0; i < tracks.length; i++)
          _Choice(_trackLabel(tracks[i].id, tracks[i].title, tracks[i].language, i),
              tracks[i].id == current.id, () => _player.setSubtitleTrack(tracks[i])),
      ],
    );
    _scheduleHide();
  }

  Future<void> _pickFrom(String title, List<_Choice> choices) async {
    if (choices.isEmpty) {
      _flash('No $title tracks');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PX.surface,
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < choices.length; i++)
                ListTile(
                  autofocus: choices[i].selected || (i == 0 && !choices.any((c) => c.selected)),
                  leading: Icon(
                    choices[i].selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: choices[i].selected ? PX.accent : PX.muted,
                  ),
                  title: Text(choices[i].label),
                  onTap: () {
                    choices[i].onPick();
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _toastTimer?.cancel();
    _player.dispose();
    _rootFocus.dispose();
    _playFocus.dispose();
    if (!_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else if (_fullscreen) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_controls && _playing && !_isDesktop) {
          _hideControls();
        } else {
          _exit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            onHover: (_) {
              if (!_controls) _showControls();
              else _scheduleHide();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _controls ? _hideControls() : _showControls(),
              onDoubleTap: _isDesktop ? _toggleFullscreen : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    controller: _video,
                    controls: NoVideoControls,
                    fill: Colors.black,
                  ),
                  if (_loading || _buffering)
                    const Center(
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(color: PX.accent, strokeWidth: 4),
                      ),
                    ),
                  if (_error != null) _errorView(),
                  if (_toast != null)
                    Align(
                      alignment: const Alignment(0, -0.6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(_toast!, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: ExcludeFocus(excluding: !_controls, child: _overlay()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: PX.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: PX.accent, size: 40),
            const SizedBox(height: 12),
            Text('Could not play this file', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: PX.muted)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CtlButton(icon: Icons.refresh, label: 'Retry', autofocus: true,
                    onTap: () => _start(resume: true)),
                const SizedBox(width: 12),
                _CtlButton(icon: Icons.arrow_back, label: 'Back', onTap: _exit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    final hasNext = _index + 1 < widget.playlist.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Colors.transparent, Color(0xE6000000)],
          stops: [0, 0.22, 0.6, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Row(
                children: [
                  _CtlButton(icon: Icons.arrow_back, onTap: _exit),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        if (_item.subtitle.isNotEmpty)
                          Text(_item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PX.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _ProgressBar(
                position: _pos,
                duration: _dur,
                onSeek: (d) {
                  _player.seek(d);
                  _scheduleHide();
                },
                onStep: _seekBy,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${formatDuration(_pos)} / ${formatDuration(_dur)}',
                      style: const TextStyle(color: PX.muted)),
                  const Spacer(),
                  _CtlButton(icon: Icons.replay_10, onTap: () => _seekBy(-10)),
                  const SizedBox(width: 10),
                  _CtlButton(
                    icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    big: true,
                    focusNode: _playFocus,
                    onTap: _togglePlay,
                  ),
                  const SizedBox(width: 10),
                  _CtlButton(icon: Icons.forward_30, onTap: () => _seekBy(30)),
                  if (hasNext) ...[
                    const SizedBox(width: 10),
                    _CtlButton(
                      icon: Icons.skip_next_rounded,
                      onTap: () {
                        _saveProgress();
                        setState(() => _index++);
                        _start(resume: true);
                      },
                    ),
                  ],
                  const Spacer(),
                  _CtlButton(icon: Icons.audiotrack_rounded, onTap: _pickAudio),
                  const SizedBox(width: 10),
                  _CtlButton(icon: Icons.subtitles_rounded, onTap: _pickSubtitle),
                  if (_isDesktop) ...[
                    const SizedBox(width: 10),
                    _CtlButton(
                      icon: _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      onTap: _toggleFullscreen,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice {
  final String label;
  final bool selected;
  final VoidCallback onPick;
  _Choice(this.label, this.selected, this.onPick);
}

/// Round control button with a visible focus ring for TV remotes.
class _CtlButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool big;
  final bool autofocus;
  final FocusNode? focusNode;

  const _CtlButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.big = false,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<_CtlButton> createState() => _CtlButtonState();
}

class _CtlButtonState extends State<_CtlButton> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.big ? 64.0 : 48.0;
    final on = _focused || _hover;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (f) => setState(() => _focused = f),
      onShowHoverHighlight: (h) => setState(() => _hover = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: size,
          padding: EdgeInsets.symmetric(horizontal: widget.label == null ? 0 : 18),
          constraints: BoxConstraints(minWidth: size),
          decoration: BoxDecoration(
            color: _focused ? PX.accent : (on ? Colors.white24 : Colors.white10),
            borderRadius: BorderRadius.circular(size / 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: widget.big ? 38 : 26, color: _focused ? Colors.black : Colors.white),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(widget.label!,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: _focused ? Colors.black : Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Seek bar: drag/tap with mouse or touch, left/right with the remote.
class _ProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<int> onStep;

  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onStep,
  });

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  bool _focused = false;
  double? _drag;

  double get _value {
    if (_drag != null) return _drag!;
    final d = widget.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (widget.position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  void _seekTo(double frac) {
    final d = widget.duration.inMilliseconds;
    if (d <= 0) return;
    widget.onSeek(Duration(milliseconds: (d * frac.clamp(0.0, 1.0)).round()));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onStep(-10);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onStep(30);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekTo(d.localPosition.dx / w),
          onHorizontalDragStart: (d) => setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) => setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) _seekTo(_drag!);
            setState(() => _drag = null);
          },
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: _focused ? 8 : 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _value,
                  child: Container(
                    height: _focused ? 8 : 5,
                    decoration: BoxDecoration(
                      gradient: PX.fire,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: (w * _value - (_focused ? 10 : 7)).clamp(0.0, w - 14),
                  child: Container(
                    width: _focused ? 20 : 14,
                    height: _focused ? 20 : 14,
                    decoration: BoxDecoration(
                      color: _focused ? PX.accent2 : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: _focused
                          ? [BoxShadow(color: PX.accent.withOpacity(0.6), blurRadius: 12)]
                          : const [],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
