import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Full-screen modal states that sit over a blurred, darkened app: the
/// spinner shown while a request is in flight, and the confirmation shown
/// when one succeeds.
///
/// Both use [showGeneralDialog] rather than [showDialog] so the barrier can
/// carry a [BackdropFilter] — a plain dialog only dims what is behind it.

/// Wraps [child] in the shared blur + dim barrier.
Widget _blurred(Widget child) {
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
    child: Container(
      color: Colors.black.withOpacity(0.45),
      child: Center(child: child),
    ),
  );
}

/// Blocks the screen while something is verifying. Dismissed by calling
/// [hideBlockingLoader] — never by the user, which is the point: the work it
/// covers must finish before anything else can be tapped.
///
/// Returns the future for the pushed route; callers normally ignore it.
Future<void> showBlockingLoader(BuildContext context, String message) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: message,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, __) {
      return FadeTransition(
        opacity: animation,
        child: PopScope(
          canPop: false,
          child: _blurred(
            Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 38,
                    width: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Closes whatever [showBlockingLoader] put up. Safe to call once per show.
void hideBlockingLoader(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pop();
}

/// The confirmation card: a mint check in a ring, a title, the caller's
/// message, and the single button that carries the patient onward.
///
/// Resolves when the button is tapped (or the barrier is dismissed), so the
/// caller can navigate immediately afterwards.
Future<void> showSuccessOverlay(
  BuildContext context, {
  String title = 'Success',
  required String message,
  String ctaLabel = 'Continue',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, __) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: _blurred(
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curve),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 76,
                    width: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.12),
                      border: Border.all(color: AppColors.primary, width: 2.5),
                    ),
                    child: Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        ctaLabel,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
