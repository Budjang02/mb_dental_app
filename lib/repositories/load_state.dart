import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/network_service.dart';

/// The parts of the record that load, fail and retry on their own.
///
/// A realtime change refreshes just its own section, and a screen shows a
/// loading, empty or error state for just its own section — an edit to one
/// table never pulls the whole chart down again, and a failed read of one
/// never takes a page down.
enum SyncSection {
  appointments,
  billing,
  wallet,
  chart,
  treatmentPlan,
  documents,
  messages,

  /// The patient's own details: the `patients` chart header and the `profiles`
  /// row behind it.
  profile,

  /// Rows from `notifications` plus the read state behind the bell.
  notifications,
}

/// Where one part of the patient's record has got to.
///
/// Held per section rather than once for the whole app: a failed read of the
/// chart says nothing about the wallet, and the page that shows the wallet must
/// not be taken down because the chart could not be fetched.
enum LoadPhase {
  /// Nothing has been asked for yet.
  idle,

  /// A request is out.
  loading,

  /// The request came back. The section's data is what the server holds — an
  /// empty list here means the patient genuinely has no rows, never a failure.
  ready,

  /// The request failed. Whatever the section still holds is from an earlier
  /// load, so it must not be presented as current.
  failed,
}

/// Why a request failed, which decides whether retrying it can ever help.
enum LoadFailure {
  /// The device has no route to the server.
  offline,

  /// The server was reachable but did not answer in time.
  timeout,

  /// No valid session. Retrying is pointless until the patient signs in again.
  unauthenticated,

  /// The account has no patient chart linked to it yet. The clinic has to act;
  /// retrying does not help.
  noPatientRecord,

  /// Row-level security refused the read. A bug or a policy gap, not something
  /// the patient can retry their way out of.
  permission,

  /// The table, column or relationship the query names is not in this project.
  /// A deployment problem; retrying cannot fix it.
  schema,

  /// The request itself is invalid (HTTP 400). Retrying cannot correct it.
  request,

  /// Anything else — a 5xx, a parse error, an unexpected exception.
  server,
}

/// One section's phase, plus what to tell the patient when it failed.
@immutable
class SectionStatus {
  final LoadPhase phase;

  /// Null unless [phase] is [LoadPhase.failed].
  final LoadFailure? failure;

  /// A short, patient-facing sentence. Never carries table names, SQL, ids or
  /// tokens — the technical detail goes to [debugPrint] instead.
  final String? message;

  const SectionStatus._(this.phase, {this.failure, this.message});

  static const SectionStatus idle = SectionStatus._(LoadPhase.idle);
  static const SectionStatus loading = SectionStatus._(LoadPhase.loading);
  static const SectionStatus ready = SectionStatus._(LoadPhase.ready);

  factory SectionStatus.failed(LoadFailure failure, String message) =>
      SectionStatus._(LoadPhase.failed, failure: failure, message: message);

  bool get isIdle => phase == LoadPhase.idle;
  bool get isLoading => phase == LoadPhase.loading;
  bool get isReady => phase == LoadPhase.ready;
  bool get hasFailed => phase == LoadPhase.failed;

  /// True while nothing trustworthy has arrived yet, so a screen should show a
  /// skeleton rather than an empty state that would read as "you have none".
  bool get isPending => phase == LoadPhase.idle || phase == LoadPhase.loading;

  /// False for the failures a retry button cannot resolve. Those still show a
  /// message; they just do not offer to try again.
  bool get isRetryable => switch (failure) {
        LoadFailure.offline || LoadFailure.timeout || LoadFailure.server => true,
        LoadFailure.permission || LoadFailure.schema || LoadFailure.request => false,
        LoadFailure.unauthenticated || LoadFailure.noPatientRecord => false,
        null => false,
      };

  @override
  bool operator ==(Object other) =>
      other is SectionStatus &&
      other.phase == phase &&
      other.failure == failure &&
      other.message == message;

  @override
  int get hashCode => Object.hash(phase, failure, message);

  @override
  String toString() => 'SectionStatus($phase${failure == null ? '' : ', $failure'})';
}

/// Turns a thrown object into the pair the UI needs: what kind of failure it
/// was, and a sentence safe to show a patient.
///
/// Deliberately the only place that decides this. Screens never read an
/// exception themselves, so a Postgres message can never reach the screen.
SectionStatus classifyFailure(Object error, {String? context}) {
  if (error is TimeoutException) {
    return SectionStatus.failed(
      LoadFailure.timeout,
      kServerConnectionMessage,
    );
  }
  if (NetworkService.isConnectionFailure(error)) {
    return SectionStatus.failed(
      LoadFailure.offline,
      kServerConnectionMessage,
    );
  }
  if (context != null) {
    // Keep browser consoles free of endpoint, token and transport details.
    debugPrint('[$context] request failed');
  }
  if (error is AuthException) {
    return SectionStatus.failed(
      LoadFailure.unauthenticated,
      'Your session has expired. Please sign in again.',
    );
  }
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // 401/PGRST301 means the session is not accepted; 403/42501 is an RLS or
    // authorization refusal. They must not be presented as connectivity.
    if (code == '401' || code == 'PGRST301') {
      return SectionStatus.failed(
        LoadFailure.unauthenticated,
        'Your session has expired. Please sign in again.',
      );
    }
    if (code == '403' || code == '42501') {
      return SectionStatus.failed(
        LoadFailure.permission,
        'You do not have access to this information. Please contact the clinic.',
      );
    }
    if (code == '400') {
      return SectionStatus.failed(
        LoadFailure.request,
        'The clinic server could not complete this request.',
      );
    }
    // 42P01 undefined_table, 42703 undefined_column, 42883 undefined_function,
    // PGRST200/PGRST202 unknown relationship or routine.
    if (code == '42P01' ||
        code == '42703' ||
        code == '42883' ||
        code.startsWith('PGRST2')) {
      return SectionStatus.failed(
        LoadFailure.schema,
        'This is not available on the clinic\'s system yet.',
      );
    }
    return SectionStatus.failed(
      LoadFailure.server,
      'The clinic server could not complete the request.',
    );
  }
  final text = error.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('timed out')) {
    return SectionStatus.failed(
      LoadFailure.timeout,
      kServerConnectionMessage,
    );
  }
  return SectionStatus.failed(
    LoadFailure.server,
    'Something went wrong on our side. Please try again.',
  );
}

/// How long any one read is given before it is treated as a timeout.
///
/// Without this a request on a stalled connection never completes and the
/// section sits on its skeleton forever — which is the state a patient reads as
/// the app being broken.
const Duration kRequestTimeout = Duration(seconds: 20);

/// Runs [request] with [kRequestTimeout], retrying only the failures a retry
/// can plausibly fix and only [attempts] times in total.
///
/// Authorization failures, invalid queries and missing tables are returned on
/// the first try: repeating them costs the patient time and cannot succeed.
Future<T> runWithRetry<T>(
  Future<T> Function() request, {
  int attempts = 2,
  Duration timeout = kRequestTimeout,
  String? context,
}) async {
  Object lastError = StateError('no attempt was made');
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      if (NetworkService.isConfigured) {
        await NetworkService.requireServerConnection();
      }
      return await request().timeout(timeout);
    } catch (e) {
      lastError = e;
      final status = classifyFailure(e);
      if (!status.isRetryable) rethrow;
      if (attempt == attempts - 1) rethrow;
      // A short, fixed back-off. Long enough for a handover between cells to
      // settle, short enough that the patient is not left waiting.
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
  throw lastError;
}
