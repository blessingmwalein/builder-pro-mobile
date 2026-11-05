import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../state/paged_catalog.dart';
import 'app_button.dart';
import 'states.dart';

/// Horizontal status filter chips (the first option is "All" = null).
class StatusFilterRow extends StatelessWidget {
  const StatusFilterRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
        ],
      ),
    );
  }
}

/// Rows of a paged list with loading, error, empty and "show more" states.
List<Widget> pagedRows<T>(
  BuildContext context, {
  required PagedState<T> state,
  required Widget Function(T item) rowBuilder,
  required Future<void> Function() onRefresh,
  required Future<void> Function() onLoadMore,
  required IconData emptyIcon,
  required String emptyTitle,
  String? emptyMessage,
}) {
  if (state.loading) return const [SkeletonList(rows: 4, rowHeight: 92)];
  if (state.error != null) {
    return [ErrorPanel(error: state.error!, compact: true, onRetry: onRefresh)];
  }
  if (state.items.isEmpty) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: Space.x3),
        child: EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          message: emptyMessage,
        ),
      ),
    ];
  }
  return [
    for (final item in state.items)
      Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: rowBuilder(item),
      ),
    if (state.loadMoreError != null)
      ErrorPanel(
        error: state.loadMoreError!,
        compact: true,
        onRetry: onLoadMore,
      ),
    if (state.hasMore && state.loadMoreError == null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: AppButton(
          label: 'Show more',
          variant: AppButtonVariant.secondary,
          loading: state.loadingMore,
          onPressed: onLoadMore,
        ),
      ),
  ];
}

/// A start widget and an end widget on one line; stacked (start above end,
/// end aligned right) when the user has enlarged text, so neither is squeezed
/// out or overflows at accessibility text sizes.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({super.key, required this.start, required this.end});
  final Widget start;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          start,
          const SizedBox(height: Space.xs),
          Align(alignment: Alignment.centerRight, child: end),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: start),
        const SizedBox(width: Space.md),
        end,
      ],
    );
  }
}
