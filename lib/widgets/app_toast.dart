import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';

/// Floating, theme-aware replacement for `ScaffoldMessenger.showSnackBar`.
/// Drops in from the top as a small rounded card instead of a bar pinned to
/// the bottom of the screen, and auto-dismisses on its own.
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
  Color? color,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  final accent = color ?? (isError ? AppColors.error : AppColors.success);

  entry = OverlayEntry(
    builder: (context) => _AppToast(
      message: message,
      accent: accent,
      icon: isError ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.checkmark_circle_fill,
      onDismissed: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  final String message;
  final Color accent;
  final IconData icon;
  final VoidCallback onDismissed;

  const _AppToast({
    required this.message,
    required this.accent,
    required this.icon,
    required this.onDismissed,
  });

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2400), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 12,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 24, offset: const Offset(0, 10)),
                ],
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
}
