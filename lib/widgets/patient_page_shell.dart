import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../repositories/patient_repository.dart';
import '../services/supabase_service.dart';

/// Wraps the dashboard's tabs with the record load and pull-to-refresh, and
/// with nothing else.
///
/// This replaces the old gate, which held the whole page back until the record
/// had arrived and put a full-screen error in its place when it had not. One
/// refused table could therefore take down Home, Schedule, Wallet, Records and
/// Profile together — the patient could not even read the parts that had
/// loaded, or reach the pages that need no data at all.
///
/// The page is now always built. Each section on it reports its own loading,
/// empty and error state from [PatientRepository.statusOf], so a failed request
/// costs the patient that section and nothing more.
class PatientPageShell extends StatefulWidget {
  final Widget child;

  const PatientPageShell({super.key, required this.child});

  @override
  State<PatientPageShell> createState() => _PatientPageShellState();
}

class _PatientPageShellState extends State<PatientPageShell> {
  final PatientRepository _repository = PatientRepository();

  @override
  void initState() {
    super.initState();
    _startIfIdle();
  }

  /// Last line of defence for the load. If the record is neither present nor on
  /// its way, ask for it rather than leaving every section on a skeleton that
  /// nothing is going to resolve.
  void _startIfIdle() {
    if (!SupabaseService.isSignedIn) return;
    if (_repository.hasLoaded || _repository.isLoading) return;
    if (_repository.identityStatus.hasFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _repository.load();
    });
  }

  Future<void> _refresh() => _repository.load(force: true);

  @override
  Widget build(BuildContext context) {
    // The page itself does not depend on the record, so it is built outside the
    // listener. Only the sections inside it rebuild on a load.
    return _RefreshablePage(onRefresh: _refresh, child: widget.child);
  }
}

/// Pull-to-refresh over a page the shell does not own.
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
