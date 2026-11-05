import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../application/change_requests_providers.dart';
import '../data/change_request_models.dart';

/// A project's change requests, newest first, and a way to raise a new one.
/// Reviewing and approving them stays on the web app.
class ChangeRequestsSection extends ConsumerWidget {
  const ChangeRequestsSection({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(projectChangeRequestsProvider(projectId));
    final currency = ref.watch(currencyProvider);
    return requests.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.xl),
        child: SkeletonList(rows: 1, rowHeight: 92),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () =>
              ref.invalidate(projectChangeRequestsProvider(projectId)),
        ),
      ),
      data: (list) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('CHANGE REQUESTS ${list.length}'),
            if (list.isEmpty)
              AppCard(
                child: Text(
                  'No change requests on this project.',
                  style: AppType.body.copyWith(color: context.colors.textMuted),
                ),
              ),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _Card(
                  request: r,
                  currency: currency,
                  onTap: () => context.push(
                    '/projects/$projectId/change-requests/${r.id}',
                  ),
                ),
              ),
            const SizedBox(height: Space.sm),
            AppButton(
              label: 'Raise a change request',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  context.push('/projects/$projectId/new-change-request'),
            ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.request,
    required this.currency,
    required this.onTap,
  });
  final ChangeRequestSummary request;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final facts = [
      crTypeLabel(r.type),
      if (r.cost != null) Fmt.money(r.cost!, currency),
      if (r.days != null) '${r.days} ${r.days == 1 ? 'day' : 'days'}',
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${r.number}, ${r.title}, ${statusInfo(r.status).label}, $facts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              r.number,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(r.status),
          ),
          const SizedBox(height: Space.xs),
          Text(
            r.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.xs),
          Text(facts, style: AppType.helper.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}
