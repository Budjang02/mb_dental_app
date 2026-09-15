import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../repositories/patient_repository.dart';
import '../services/supabase_service.dart';
import 'skeleton.dart';

/// Holds back a screen until the patient's record has actually arrived.
///
/// Without this the dashboard renders an empty chart during the first load and
/// again after a failure — a blank appointment list reads as "you have no
/// appointments", which is a different and much worse message than "we could
/// not reach the clinic".
///
/// It also starts the load itself when nothing else has. Every state below —
/// the skeleton, the failure, and the page itself — pulls to refresh, so a
/// stalled load can never leave the patient on a screen that does not respond
/// to anything, and a loaded page can always be brought up to date.
class RecordLoadGate extends StatefulWidget {
  final Widget child;

  const RecordLoadGate({super.key, required this.child});

  @override
  State<RecordLoadGate> createState() => _RecordLoadGateState();
}

class _RecordLoadGateState extends State<RecordLoadGate> {
  final PatientRepository _repository = PatientRepository();

  @override
  void initState() {
    super.initState();
    _startIfIdle();
  }

  /// Last line of defence for the load. If the record is neither present nor
  /// on its way, ask for it rather than sitting on a skeleton that nothing is
  /// going to resolve.
  void _startIfIdle() {
    if (!SupabaseService.isSignedIn) return;
    if (_repository.hasLoaded || _repository.isLoading) return;
    if (_repository.loadError != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _repository.load();
    });
  }

  Future<void> _refresh() => _repository.load(force: true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repository,
      builder: (context, _) {
        if (_repository.hasLoaded) {
          return _RefreshablePage(onRefresh: _refresh, child: widget.child);
        }

        final error = _repository.loadError;
        if (error != null) {
          return _GateMessage(
            icon: CupertinoIcons.exclamationmark_circle,
            message: error,
            onRetry: _refresh,
            isBusy: _repository.isLoading,
          );
        }

        return _GateSkeleton(onRefresh: _refresh);
      },
    );
  }
}

/// Pull-to-refresh over a page the gate does not own.
///
/// Each tab builds its own scroll view, often a level or two down (inside a
/// Scaffold, or a TabBarView page), so the indicator listens to any vertical
/// scrollable beneath it rather than only a direct child. The scroll physics
/// are made always-scrollable for the same reason: a short list that fits the
/// screen must still accept the pull.
class _RefreshablePage extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const _RefreshablePage({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
      child: ScrollConfiguration(
        behavior: behavior.copyWith(
          physics: AlwaysScrollableScrollPhysics(parent: behavior.getScrollPhysics(context)),
        ),
        child: child,
      ),
    );
  }
}

/// The first load, shown as the shape of the page to come rather than a
/// spinner. Still scrolls and still pulls to refresh.
class _GateSkeleton extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _GateSkeleton({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          label: 'Loading your records',
          child: const SingleChildScrollView(
            // Always scrollable, so the pull-to-refresh gesture is available
            // even though the skeleton may fit the screen.
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: PageSkeleton(),
          ),
        ),
      ),
    );
  }
}

/// A waiting or failed state that still scrolls and still pulls to refresh.
class _GateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;
  final bool isBusy;

  const _GateMessage({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRetry,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          // Always scrollable, so the pull-to-refresh gesture is available even
          // though this content is far shorter than the screen.
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    else
                      Icon(icon, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 20),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (!isBusy) ...[
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onRetry,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
