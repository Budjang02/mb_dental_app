import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';

/// Shared floating-dialog chrome used across the app instead of ad-hoc
/// `Dialog(backgroundColor: Colors.white, ...)` or full-page bottom sheets.
/// Theme-aware (uses [AppColors.surface]) and capped in height so it never
/// covers the whole screen.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxHeightFactor = 0.82,
  double maxWidth = 420,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * maxHeightFactor,
            maxWidth: maxWidth,
          ),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

/// Small "x" dismiss button used in the top-right corner of most app dialogs.
class AppDialogCloseButton extends StatelessWidget {
  final VoidCallback? onTap;

  const AppDialogCloseButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () => Navigator.pop(context),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: AppColors.textSecondary),
      ),
    );
  }
}
