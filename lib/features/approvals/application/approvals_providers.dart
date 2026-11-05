import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../data/approval_models.dart';
import '../data/approvals_repository.dart';

final approvalsRepositoryProvider = Provider<ApprovalsRepository>(
  (ref) => ApprovalsRepository(ref.watch(apiClientProvider)),
);

class ApprovalsState {
  const ApprovalsState(
    this.entries, {
    this.page = 1,
    this.hasMore = false,
    this.total = 0,
    this.loadingMore = false,
    this.loadMoreError,
  });

  /// Entries waiting for a decision, newest first.
  final List<ApprovalEntry> entries;
  final int page;
  final bool hasMore;

  /// Pending entries on the server (may exceed what is loaded).
  final int total;
  final bool loadingMore;
  final AppException? loadMoreError;

  /// Finished shifts a supervisor can decide on now.
  List<ApprovalEntry> get ready => entries.where((e) => !e.isOpen).toList();

  /// Still clocked in: shown as "working now", not approvable yet.
  List<ApprovalEntry> get working => entries.where((e) => e.isOpen).toList();

  ApprovalsState copyWith({
    List<ApprovalEntry>? entries,
    int? page,
    bool? hasMore,
    int? total,
    bool? loadingMore,
    AppException? loadMoreError,
    bool clearLoadMoreError = false,
  }) => ApprovalsState(
    entries ?? this.entries,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

/// Time entries awaiting approval.
class ApprovalsController extends AsyncNotifier<ApprovalsState> {
  @override
  Future<ApprovalsState> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const ApprovalsState([]);
    ref.listen<int>(appResumeProvider, (_, _) => _quietRefresh());
    final page = await ref.read(approvalsRepositoryProvider).pending();
    return ApprovalsState(
      page.entries,
      page: page.page,
      hasMore: page.hasMore,
      total: page.total,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _quietRefresh() async {
    try {
      final page = await ref.read(approvalsRepositoryProvider).pending();
      if (!ref.mounted) return;
      state = AsyncData(
        ApprovalsState(
          page.entries,
          page: page.page,
          hasMore: page.hasMore,
          total: page.total,
        ),
      );
    } on AppException {
      // Keep what is showing.
    }
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(s.copyWith(loadingMore: true, clearLoadMoreError: true));
    try {
      final next = await ref
          .read(approvalsRepositoryProvider)
          .pending(page: s.page + 1);
      final cur = state.value ?? s;
      final known = cur.entries.map((e) => e.id).toSet();
      if (!ref.mounted) return;
      state = AsyncData(
        cur.copyWith(
          entries: [
            ...cur.entries,
            ...next.entries.where((e) => !known.contains(e.id)),
          ],
          page: next.page,
          hasMore: next.hasMore,
          total: next.total,
          loadingMore: false,
        ),
      );
    } on AppException catch (e) {
      final cur = state.value ?? s;
      if (ref.mounted) {
        state = AsyncData(cur.copyWith(loadingMore: false, loadMoreError: e));
      }
    }
  }

  /// Approves or rejects one entry. On success it leaves the list. A decision
  /// just sets a status, so after an uncertain failure it is safe to send once
  /// more; if that also fails the entry stays and the error is shown.
  Future<void> decide(
    ApprovalEntry entry, {
    required bool approve,
    String? comment,
  }) async {
    final repo = ref.read(approvalsRepositoryProvider);
    try {
      try {
        await repo.decide(entry.id, approve: approve, comment: comment);
      } on AppException catch (e) {
        if (!e.outcomeUnknown) rethrow;
        await repo.decide(entry.id, approve: approve, comment: comment);
      }
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.validation &&
          e.message.toLowerCase().contains('active clock-in')) {
        // They clocked in again, or the list was stale: show the truth.
        await _quietRefresh();
        throw const AppException(
          AppErrorKind.validation,
          'That worker is still clocked in. You can decide once they clock out.',
        );
      }
      rethrow;
    }
    final s = state.value;
    if (s == null || !ref.mounted) return;
    state = AsyncData(
      s.copyWith(
        entries: s.entries.where((e) => e.id != entry.id).toList(),
        total: s.total > 0 ? s.total - 1 : 0,
      ),
    );
  }
}

final approvalsProvider =
    AsyncNotifierProvider<ApprovalsController, ApprovalsState>(
      ApprovalsController.new,
    );

/// One worker's entries waiting for a decision.
class WorkerApprovals {
  const WorkerApprovals(this.workerId, this.workerName, this.entries);
  final String workerId;
  final String workerName;
  final List<ApprovalEntry> entries;

  double get totalHours => entries.fold(0, (s, e) => s + e.totalHours);
}

/// Groups finished entries by worker (A–Z); within a worker, newest first.
List<WorkerApprovals> groupByWorker(List<ApprovalEntry> entries) {
  final byWorker = <String, List<ApprovalEntry>>{};
  for (final e in entries) {
    byWorker.putIfAbsent(e.workerId, () => []).add(e);
  }
  final groups =
      [
        for (final list in byWorker.values)
          WorkerApprovals(
            list.first.workerId,
            list.first.workerName,
            [...list]..sort((a, b) => b.clockInAt.compareTo(a.clockInAt)),
          ),
      ]..sort(
        (a, b) =>
            a.workerName.toLowerCase().compareTo(b.workerName.toLowerCase()),
      );
  return groups;
}
