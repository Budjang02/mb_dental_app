import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../repositories/patient_repository.dart';
import 'skeleton.dart';

/// The inline states a single section of a page can be in.
///
/// Everything here is sized to sit *inside* a card or a list area. None of it
/// is full-screen, none of it replaces a page, and none of it removes the
/// header, the navigation bar or the sections beside it. A failed read of the
/// wallet is a small line inside the wallet card — the rest of the page carries
/// on working.

/// A short error line with a retry button, drawn inside the affected section.
///
/// [SectionStatus.isRetryable] decides whether a retry is even offered: a
/// permission refusal or a table that is not deployed cannot be retried into
/// working, and a button that never helps is worse than no button.
class SectionErrorNotice extends StatelessWidget {
  final SectionStatus status;
  final Future<void> Function() onRetry;

  /// True while the retry is out, so the button shows a spinner and refuses
  /// further presses rather than stacking duplicate requests.
  final bool isRetrying;

  /// Tightens the padding for a notice inside an already-padded card.
  final bool compact;

  const SectionErrorNotice({
    super.key,
    required this.status,
    required this.onRetry,
    this.isRetrying = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = status.message ?? 'We could not load this just now.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.exclamationmark_circle, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textPrimary),
                ),
                if (status.isRetryable) ...[
                  const SizedBox(height: 8),
                  _RetryButton(onRetry: onRetry, isRetrying: isRetrying),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single-line version for a card that has no room for a block — the wallet
/// balance, say, where the figure itself is what could not be confirmed.
class SectionErrorLine extends StatelessWidget {
  final SectionStatus status;
  final Future<void> Function() onRetry;
  final bool isRetrying;

  /// Drawn on the coloured balance card, where the page's text colours would
  /// disappear into the gradient.
  final Color? foreground;

  const SectionErrorLine({
    super.key,
    required this.status,
    required this.onRetry,
    this.isRetrying = false,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? AppColors.textSecondary;
    return Row(
      children: [
        Icon(CupertinoIcons.exclamationmark_circle, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            status.message ?? 'Could not be loaded.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.3, color: color),
          ),
        ),
        if (status.isRetryable) ...[
          const SizedBox(width: 8),
          _RetryButton(onRetry: onRetry, isRetrying: isRetrying, foreground: foreground),
        ],
      ],
    );
  }
}

/// Small, quiet, and the same everywhere. Disabled while its request is out, so
/// repeated taps cannot queue a second one.
class _RetryButton extends StatelessWidget {
  final Future<void> Function() onRetry;
  final bool isRetrying;
  final Color? foreground;

  const _RetryButton({required this.onRetry, required this.isRetrying, this.foreground});

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? AppColors.primary;
    if (isRetrying) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
            const SizedBox(width: 8),
            Text(
              'Retrying',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onRetry(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.arrow_clockwise, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                'Try Again',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A placeholder in the shape of the rows that are coming, shown inside the
/// section while its request is out.
class SectionSkeleton extends StatelessWidget {
  final int rows;

  const SectionSkeleton({super.key, this.rows = 2});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        children: [for (var i = 0; i < rows; i++) const SkeletonCard()],
      ),
    );
  }
}

/// The empty state every section uses: an icon, a heading, and a line of
/// explanation. The same shape the Records and Treatment Plan tabs already had,
/// lifted out so every section says it the same way.
class SectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;

  /// Matches the inset well the Records tabs draw their empty state in.
  final bool boxed;

  const SectionEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Icon(icon, size: 36, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );

    if (!boxed) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: content,
    );
  }
}
