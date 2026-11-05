import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/reason_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/state/paged_catalog.dart';
import '../application/requests_providers.dart';
import '../data/request_models.dart';

/// Requests waiting for the signed-in user's decision (purchase orders, change
/// requests…). Decisions are never queued offline.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  final _busy = <String>{};

  RequestsCatalog get _catalog => ref.read(requestsCatalogProvider.notifier);

  Future<void> _decide(
    ApprovalRequest r, {
    required bool approve,
    String? comment,
  }) async {
    if (!_busy.add(r.id)) return;
    setState(() {});
    try {
      final note = await _catalog.decide(r, approve: approve, comment: comment);
      if (mounted) {
        Snack.show(context, note ?? (approve ? 'Approved.' : 'Rejected.'));
      }
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      _busy.remove(r.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _approve(ApprovalRequest r) async {
    final known = ref
        .read(requestContextProvider((type: r.entityType, id: r.entityId)))
        .value;
    final ok = await confirmAction(
      context,
      title: 'Approve this ${r.typeLabel.toLowerCase()}?',
      message: [
        'Requested by ${r.requestedBy}.',
        known != null ? '$known.' : 'This app does not show what is being approved, so check the details on the web app if you are not sure.',
        ?approvalEffect(r.entityType),
      ].join(' '),
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    await _decide(r, approve: true);
  }

  Future<void> _reject(ApprovalRequest r) async {
    final reason = await showReasonSheet(
      context,
      title: 'Reject this ${r.typeLabel.toLowerCase()}?',
      subtitle:
          'Requested by ${r.requestedBy}. Rejecting stops the whole request.',
      confirmLabel: 'Reject',
      hint: 'Tell them why',
    );
    if (reason == null || !mounted) return;
    await _decide(r, approve: false, comment: reason);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(requestsCatalogProvider);
    final me = ref.watch(currentUserIdProvider);
    final c = context.colors;

    return PageBody(
      onRefresh: _catalog.refresh,
      children: [
        PageTitle(
          'Requests',
          subtitle: state.items.isEmpty
              ? null
              : '${state.items.length} waiting for you',
        ),
        AppCard(
          color: c.surfaceMuted,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: Sizes.iconSm,
                color: c.textMuted,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  'You can approve or reject here. For purchase requests and orders the app shows what is being asked for; for other kinds it shows only who asked and any note, so open those on the web app to see the details.',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        ..._list(state, me),
      ],
    );
  }

  List<Widget> _list(PagedState<ApprovalRequest> state, String? me) {
    if (state.loading) return const [SkeletonList(rows: 3, rowHeight: 130)];
    if (state.error != null) {
      return [
        ErrorPanel(
          error: state.error!,
          compact: true,
          onRetry: _catalog.refresh,
        ),
      ];
    }
    if (state.items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: Space.x3),
          child: EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Nothing waiting for you',
            message: 'Requests that need your decision will appear here.',
          ),
        ),
      ];
    }
    return [
      for (final r in state.items)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: _RequestCard(
            request: r,
            mine: me == null ? null : r.pendingStepFor(me),
            busy: _busy.contains(r.id),
            onApprove: () => _approve(r),
            onReject: () => _reject(r),
          ),
        ),
      if (state.loadMoreError != null)
        ErrorPanel(
          error: state.loadMoreError!,
          compact: true,
          onRetry: _catalog.loadMore,
        ),
      if (state.hasMore && state.loadMoreError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: AppButton(
            label: 'Show more',
            variant: AppButtonVariant.secondary,
            loading: state.loadingMore,
            onPressed: _catalog.loadMore,
          ),
        ),
    ];
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({
    required this.request,
    required this.mine,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalRequest request;
  final RequestStep? mine;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final r = request;
    final done = r.steps.where((s) => s.status == 'APPROVED').length;
    final about = ref
        .watch(requestContextProvider((type: r.entityType, id: r.entityId)))
        .value;
    return AppCard(
      semanticLabel:
          '${r.typeLabel} requested by ${r.requestedBy}, ${Fmt.ago(r.createdAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(Icons.approval_outlined),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.typeLabel,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    Text(
                      '${r.requestedBy} · ${Fmt.ago(r.createdAt)}',
                      style: AppType.bodySmall.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (about != null) ...[
            const SizedBox(height: Space.md),
            Text(about, style: AppType.bodyStrong.copyWith(color: c.text)),
          ],
          if (r.notes != null) ...[
            const SizedBox(height: Space.md),
            Text(r.notes!, style: AppType.body.copyWith(color: c.text)),
          ],
          if (r.steps.length > 1) ...[
            const SizedBox(height: Space.sm),
            Text(
              '$done of ${r.steps.length} approvers have approved',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ],
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              AppButton(
                label: 'Reject',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: busy || mine == null ? null : onReject,
              ),
              AppButton(
                label: 'Approve',
                compact: true,
                expand: false,
                icon: Icons.check_rounded,
                loading: busy,
                onPressed: busy || mine == null ? null : onApprove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
