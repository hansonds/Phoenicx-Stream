import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Network image with a dark placeholder.
class NetImg extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final String? fallbackText;
  const NetImg(this.url,
      {super.key, this.fit = BoxFit.cover, this.fallbackIcon = Icons.movie_outlined, this.fallbackText});

  Widget _fallback() => Container(
        color: PX.surface2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: fallbackText == null
            ? Icon(fallbackIcon, color: PX.muted, size: 32)
            : Text(fallbackText!,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PX.muted, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    if (url == null) return _fallback();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => Container(color: PX.surface2),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }
}

/// A card that works with touch, mouse and TV remote (D-pad + OK).
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final double radius;
  final double focusScale;
  final FocusNode? focusNode;

  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocus,
    this.autofocus = false,
    this.radius = 12,
    this.focusScale = 1.06,
    this.focusNode,
  });

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocus?.call(f);
      },
      onShowHoverHighlight: (h) => setState(() => _hover = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: active ? widget.focusScale : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius + 3),
              border: Border.all(
                color: _focused ? PX.accent : Colors.transparent,
                width: 3,
              ),
              boxShadow: _focused
                  ? [BoxShadow(color: PX.accent.withOpacity(0.35), blurRadius: 18, spreadRadius: 1)]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Poster (2:3) with a title under it.
class PosterCard extends StatelessWidget {
  final String? image;
  final String title;
  final String? caption;
  final double width;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final double? progress;

  const PosterCard({
    super.key,
    required this.image,
    required this.title,
    required this.width,
    required this.onTap,
    this.caption,
    this.onFocus,
    this.autofocus = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusCard(
            onTap: onTap,
            onFocus: onFocus,
            autofocus: autofocus,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImg(image, fallbackText: title),
                  if (progress != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.black54,
                        color: PX.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (caption != null)
            Text(caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PX.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Wide (16:9) card used for Continue Watching.
class WideCard extends StatelessWidget {
  final String? image;
  final String title;
  final String? caption;
  final double width;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;

  const WideCard({
    super.key,
    required this.image,
    required this.title,
    required this.width,
    required this.onTap,
    this.onLongPress,
    this.caption,
    this.progress,
    this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusCard(
            onTap: onTap,
            onLongPress: onLongPress,
            onFocus: onFocus,
            focusScale: 1.04,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImg(image, fallbackIcon: Icons.play_circle_outline),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  const Center(child: Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white70)),
                  if (progress != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.black54,
                        color: PX.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (caption != null)
            Text(caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PX.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Focusable pill button (works with remote).
class PillButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;
  final bool selected;
  final FocusNode? focusNode;

  const PillButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return FocusCard(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      radius: 24,
      focusScale: 1.05,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: primary ? PX.fire : null,
          color: primary ? null : (selected ? PX.accent.withOpacity(0.22) : PX.surface2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: primary ? Colors.black : PX.text),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.black : (selected ? PX.accent2 : PX.text),
                )),
          ],
        ),
      ),
    );
  }
}

/// Section title + horizontal row.
class ShelfRow extends StatelessWidget {
  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemSpacing;

  const ShelfRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.itemSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final pad = Layout.pad(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 8),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
            itemCount: itemCount,
            separatorBuilder: (_, __) => SizedBox(width: itemSpacing),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

/// Round focusable icon button.
class RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool autofocus;
  final double size;
  const RoundIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.autofocus = false,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final child = FocusCard(
      onTap: onTap,
      autofocus: autofocus,
      radius: size / 2,
      focusScale: 1.08,
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withOpacity(0.45),
        child: Icon(icon, color: Colors.white, size: size * 0.52),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Back + Home buttons shown at the top of every inner screen.
class NavButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  const NavButtons({super.key, this.onBack, this.onHome});

  static void goHome(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundIcon(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        RoundIcon(
          icon: Icons.home_rounded,
          tooltip: 'Home',
          onTap: onHome ?? () => goHome(context),
        ),
      ],
    );
  }
}
