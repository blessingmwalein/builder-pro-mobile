import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/status_badge.dart';
import '../application/equipment_providers.dart';
import '../data/equipment_models.dart';

/// The company's equipment and where it is. With `materials.manage` you can
/// add equipment and open an item to edit it, assign it or change its status.
class EquipmentScreen extends ConsumerWidget {
  const EquipmentScreen({super.key});

  static const _filters = <(String?, String)>[
    (null, 'All'),
    (EquipmentStatus.available, 'Available'),
    (EquipmentStatus.inUse, 'In use'),
    (EquipmentStatus.maintenance, 'Maintenance'),
    (EquipmentStatus.retired, 'Retired'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(equipmentCatalogProvider);
    final notifier = ref.read(equipmentCatalogProvider.notifier);
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Equipment'),
        if (ref.watch(permissionsProvider).hasAny(Feature.equipmentManage)) ...[
          AppButton(
            label: 'Add equipment',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/equipment/new'),
          ),
          const SizedBox(height: Space.md),
        ],
        StatusFilterRow(
          options: _filters,
          selected: state.filter,
          onSelected: notifier.setFilter,
        ),
        const SizedBox(height: Space.md),
        ...pagedRows<EquipmentSummary>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.construction_outlined,
          emptyTitle: state.filter == null
              ? 'No equipment yet'
              : 'No equipment with that status',
          emptyMessage: state.filter == null
              ? (ref.watch(permissionsProvider).hasAny(Feature.equipmentManage)
                    ? 'Add the first piece of equipment above.'
                    : 'Equipment is added by someone who manages materials.')
              : null,
          rowBuilder: (e) => _EquipmentCard(
            equipment: e,
            onTap: () => context.push('/equipment/${e.id}'),
          ),
        ),
      ],
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.equipment, required this.onTap});
  final EquipmentSummary equipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = equipment;
    final detail = [
      if (e.categoryName != null) e.categoryName!,
      if (e.serialNumber != null) 'Serial ${e.serialNumber}',
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${e.name}, ${statusInfo(e.status).label}${detail.isEmpty ? '' : ', $detail'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              e.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(e.status),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                detail,
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
