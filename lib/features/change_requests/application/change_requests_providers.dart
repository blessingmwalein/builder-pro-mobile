import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../finance/application/finance_providers.dart';
import '../../projects/application/projects_providers.dart';
import '../data/change_request_models.dart';
import '../data/change_requests_repository.dart';

final changeRequestsRepositoryProvider = Provider<ChangeRequestsRepository>(
  (ref) => ChangeRequestsRepository(ref.watch(apiClientProvider)),
);

/// A project's change requests.
final projectChangeRequestsProvider = FutureProvider.autoDispose
    .family<List<ChangeRequestSummary>, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(changeRequestsRepositoryProvider).list(projectId);
    });

/// One change request of a project.
final changeRequestDetailProvider = FutureProvider.autoDispose
    .family<ChangeRequestDetail, ({String projectId, String id})>((ref, key) {
      ref.watch(currentUserIdProvider);
      return ref
          .watch(changeRequestsRepositoryProvider)
          .get(key.projectId, key.id);
    });

/// Result of "new change request".
class NewChangeRequestResult {
  const NewChangeRequestResult(
    this.request, {
    this.submitted = false,
    this.note,
    this.submitError,
  });

  final ChangeRequestSummary request;

  /// It was also submitted for review (not just saved as a draft).
  final bool submitted;

  /// Explains a recovered outcome (the first reply never arrived).
  final String? note;

  /// The draft was saved but submitting it failed; the draft is not lost.
  final AppException? submitError;
}

/// Raising and submitting change requests.
class ChangeRequestActions {
  ChangeRequestActions(this._ref);
  final Ref _ref;

  ChangeRequestsRepository get _repo =>
      _ref.read(changeRequestsRepositoryProvider);

  /// Creates a draft and, when [submit] is set, submits it for review.
  ///
  /// Creating cannot be repeated (it would raise a second request), so after an
  /// uncertain failure the project's requests are read back: one of the user's
  /// own with the same title, made in the last two minutes, means it arrived.
  Future<NewChangeRequestResult> create(
    String projectId, {
    required String title,
    required String description,
    required String type,
    List<NewCrItem> items = const [],
    bool submit = false,
  }) async {
    final me = _ref.read(currentUserIdProvider);
    final startedAt = DateTime.now();
    ChangeRequestSummary created;
    String? note;
    try {
      created = await _repo.create(
        projectId,
        title: title,
        description: description,
        type: type,
        items: items,
      );
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      List<ChangeRequestSummary>? fresh;
      try {
        fresh = await _repo.list(projectId);
      } on AppException {
        fresh = null;
      }
      // Could not even ask: the outcome stays unknown.
      if (fresh == null) rethrow;
      final since = startedAt.subtract(const Duration(minutes: 2));
      final match = fresh
          .where(
            (r) =>
                r.title == title.trim() &&
                r.requestedById == me &&
                r.createdAt.isAfter(since),
          )
          .firstOrNull;
      if (match == null) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and no change request was created. Please try again.",
        );
      }
      created = match;
      note = 'The change request was saved. The confirmation was slow, so we checked.';
    }
    _ref.invalidate(projectChangeRequestsProvider(projectId));
    if (!submit) return NewChangeRequestResult(created, note: note);
    try {
      final submitNote = await this.submit(projectId, created.id);
      return NewChangeRequestResult(
        created,
        submitted: true,
        note: submitNote ?? note,
      );
    } on AppException catch (e) {
      return NewChangeRequestResult(created, note: note, submitError: e);
    }
  }

  /// DRAFT → SUBMITTED. A repeat answers 400, so after a timeout the request is
  /// read back: no longer a draft means it went. Returns a note when the
  /// outcome needs explaining; throws when nothing was recorded.
  Future<String?> submit(String projectId, String id) async {
    try {
      await _repo.submit(projectId, id);
      _refresh(projectId, id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        ChangeRequestDetail? fresh;
        try {
          fresh = await _repo.get(projectId, id);
        } on AppException {
          fresh = null;
        }
        if (fresh == null) rethrow;
        if (fresh.summary.status != CrStatus.draft) {
          _refresh(projectId, id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was recorded. Please try again.",
        );
      }
      if (e.kind == AppErrorKind.validation) {
        _refresh(projectId, id);
        throw const AppException(
          AppErrorKind.validation,
          'This change request has already moved on. The page now shows its current state.',
        );
      }
      rethrow;
    }
  }

  /// SUBMITTED → UNDER_REVIEW with the reviewer's optional estimate.
  Future<String?> review(
    String projectId,
    String id, {
    double? estimatedCost,
    int? estimatedDays,
    String? notes,
  }) => _transition(
    projectId,
    id,
    from: CrStatus.submitted,
    to: CrStatus.underReview,
    send: () => _repo.review(
      projectId,
      id,
      estimatedCost: estimatedCost,
      estimatedDays: estimatedDays,
      notes: notes,
    ),
    mine: (d, me, since) =>
        _by(d.reviewedById, me) && _since(d.reviewedAt, since),
  );

  /// UNDER_REVIEW → APPROVED. A cost above zero is added to the project's
  /// budget and days above zero push its end date later, so the project and
  /// its budget are refreshed afterwards.
  Future<String?> approve(
    String projectId,
    String id, {
    double? approvedCost,
    int? approvedDays,
    String? notes,
  }) => _transition(
    projectId,
    id,
    from: CrStatus.underReview,
    to: CrStatus.approved,
    affectsProject: true,
    send: () => _repo.approve(
      projectId,
      id,
      approvedCost: approvedCost,
      approvedDays: approvedDays,
      notes: notes,
    ),
    mine: (d, me, since) =>
        _by(d.approvedById, me) && _since(d.approvedAt, since),
  );

  /// → REJECTED, with the reason for the requester. The app offers it only
  /// while a request is under review (see backend-gaps G47).
  Future<String?> reject(
    String projectId,
    String id, {
    required String notes,
  }) => _transition(
    projectId,
    id,
    from: CrStatus.underReview,
    to: CrStatus.rejected,
    send: () => _repo.reject(projectId, id, notes: notes),
    mine: (d, me, since) =>
        _by(d.approvedById, me) && _since(d.rejectedAt, since),
  );

  /// APPROVED → IMPLEMENTED. The server records no one for this step, so after
  /// a timeout only the time of the change can be checked.
  Future<String?> implement(String projectId, String id) => _transition(
    projectId,
    id,
    from: CrStatus.approved,
    to: CrStatus.implemented,
    send: () => _repo.implement(projectId, id),
    mine: (d, me, since) => _since(d.implementedAt, since),
  );

  /// The server recorded [recorded] as the person, or recorded no one at all
  /// (until B6 is live it cannot), in which case only the time can be checked.
  static bool _by(String recorded, String? me) =>
      recorded.isEmpty || recorded == me;

  static bool _since(DateTime? at, DateTime since) =>
      at != null && at.isAfter(since);

  /// One status change, sent once. A repeat answers 400, so after a timeout the
  /// request is read back: moved to [to] by this person just now means it went
  /// through; still in [from] means nothing was recorded; anything else means a
  /// colleague got there first. Returns a note when the outcome needs
  /// explaining; throws when nothing was recorded by this send.
  Future<String?> _transition(
    String projectId,
    String id, {
    required String from,
    required String to,
    required Future<void> Function() send,
    required bool Function(ChangeRequestDetail d, String? me, DateTime since)
    mine,
    bool affectsProject = false,
  }) async {
    final me = _ref.read(currentUserIdProvider);
    final startedAt = DateTime.now();
    try {
      await send();
      _refresh(projectId, id, affectsProject: affectsProject);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        ChangeRequestDetail? fresh;
        try {
          fresh = await _repo.get(projectId, id);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final status = fresh.summary.status;
        if (status == to &&
            mine(fresh, me, startedAt.subtract(const Duration(minutes: 3)))) {
          _refresh(projectId, id, affectsProject: affectsProject);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (status == from) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _refresh(projectId, id, affectsProject: affectsProject);
        throw const AppException(
          AppErrorKind.validation,
          'This change request was already handled by someone else. The page now shows its current state.',
        );
      }
      if (e.kind == AppErrorKind.validation) {
        _refresh(projectId, id, affectsProject: affectsProject);
        throw const AppException(
          AppErrorKind.validation,
          'This change request has already moved on. The page now shows its current state.',
        );
      }
      rethrow;
    }
  }

  void _refresh(String projectId, String id, {bool affectsProject = false}) {
    _ref.invalidate(projectChangeRequestsProvider(projectId));
    _ref.invalidate(
      changeRequestDetailProvider((projectId: projectId, id: id)),
    );
    if (affectsProject) {
      // Approving can add to the budget and push the end date.
      _ref.invalidate(projectDetailProvider(projectId));
      _ref.invalidate(projectBudgetProvider(projectId));
      _ref.invalidate(companyDashboardProvider);
    }
  }
}

final changeRequestActionsProvider = Provider<ChangeRequestActions>(
  (ref) => ChangeRequestActions(ref),
);
