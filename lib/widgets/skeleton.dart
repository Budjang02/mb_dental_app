import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Pulses its [child] between two opacities so grey placeholder blocks read
/// as "loading" rather than as an empty page.
///
/// One animation drives a whole skeleton, so every block in it breathes in
/// step instead of each shimmering on its own clock.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// A single placeholder block. Sized by its parent when [width] or [height]
/// is left null.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonBox({super.key, this.width, this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped placeholder: a title line, two shorter lines under it.
/// The shape every list in the app settles into once its rows arrive.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 14)),
              SizedBox(width: 40),
              SkeletonBox(width: 60, height: 18, radius: 8),
            ],
          ),
          SizedBox(height: 12),
          FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 11)),
          SizedBox(height: 8),
          FractionallySizedBox(widthFactor: 0.8, child: SkeletonBox(height: 11)),
        ],
      ),
    );
  }
}

/// A whole page in placeholder form: a header block, a feature card, then a
/// list of [SkeletonCard]s. Shown while a page's data is still on its way.
class PageSkeleton extends StatelessWidget {
  final int cardCount;

  /// Whether to lead with the header and large feature card. Off for plain
  /// lists, which have no hero area to stand in for.
  final bool showHeader;

  const PageSkeleton({super.key, this.cardCount = 4, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            const Row(
              children: [
                SkeletonBox(width: 44, height: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
                      SizedBox(height: 8),
                      FractionallySizedBox(widthFactor: 0.7, child: SkeletonBox(height: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SkeletonBox(height: 140, radius: 16),
            const SizedBox(height: 24),
            const FractionallySizedBox(widthFactor: 0.35, child: SkeletonBox(height: 14)),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < cardCount; i++) const SkeletonCard(),
        ],
      ),
    );
  }
}
