import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../application/clients_providers.dart';
import '../data/client_models.dart';

/// The company's clients and how to reach them. With `crm.manage` you can add
/// a client and edit one from its page.
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The search text as a filter: none when it is blank.
  String? _filterFor(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(clientsCatalogProvider.notifier).setFilter(_filterFor(text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientsCatalogProvider);
    final notifier = ref.read(clientsCatalogProvider.notifier);
    final searching = state.filter != null;
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Clients'),
        if (ref.watch(permissionsProvider).hasAny(Feature.crmManage)) ...[
          AppButton(
            label: 'Add client',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/clients/new'),
          ),
          const SizedBox(height: Space.md),
        ],
        AppTextField(
          label: 'Search clients',
          controller: _search,
          hint: 'Name or email',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _onSearch,
          onSubmitted: (t) => notifier.setFilter(_filterFor(t)),
        ),
        const SizedBox(height: Space.md),
        ...pagedRows<ClientSummary>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.groups_2_outlined,
          emptyTitle: searching ? 'No clients match' : 'No clients yet',
          emptyMessage: searching
              ? 'Try a different name or email.'
              : (ref.watch(permissionsProvider).hasAny(Feature.crmManage)
                    ? 'Add the first client above.'
                    : 'Clients are added by someone who manages them.'),
          rowBuilder: (c) => _ClientCard(
            client: c,
            onTap: () => context.push('/clients/${c.id}'),
          ),
        ),
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap});
  final ClientSummary client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = client;
    String plural(int n, String one, String many) =>
        '$n ${n == 1 ? one : many}';
    final who = [
      if (k.contactPerson != null) k.contactPerson!,
      clientTypeLabel(k.type),
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      semanticLabel: '${k.name}, $who',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyStrong.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.xs),
          Text(who, style: AppType.bodySmall.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.sm),
          Text(
            [
              plural(k.projectCount, 'project', 'projects'),
              plural(k.quoteCount, 'quote', 'quotes'),
              plural(k.invoiceCount, 'invoice', 'invoices'),
            ].join(' · '),
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
