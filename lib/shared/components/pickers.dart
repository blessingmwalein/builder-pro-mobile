import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

/// A tappable "field" that opens a picker. Looks like [AppTextField] so forms
/// stay consistent; shows [value] or the [placeholder].
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.placeholder = 'Select',
    this.icon,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final String placeholder;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppType.label.copyWith(color: c.text)),
        const SizedBox(height: Space.sm - 2),
        Semantics(
          button: true,
          enabled: enabled,
          label: '$label, ${hasValue ? value : placeholder}',
          excludeSemantics: true,
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Corners.md),
              side: BorderSide(color: c.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.inputHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: Sizes.iconMd, color: c.textMuted),
                        const SizedBox(width: Space.md),
                      ],
                      Expanded(
                        child: Text(
                          hasValue ? value! : placeholder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body.copyWith(
                            color: hasValue ? c.text : c.textMuted,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: Sizes.iconMd,
                        color: c.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One option in [pickOne].
class PickerOption<T> {
  const PickerOption({required this.value, required this.title, this.subtitle});
  final T value;
  final String title;
  final String? subtitle;
}

/// Bottom-sheet single choice. Returns null when dismissed. [allowClear] adds a
/// first row that returns [clearValue] (for optional selections).
Future<({T? value})?> pickOne<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String? clearLabel,
  String? emptyMessage,
}) {
  return showModalBottomSheet<({T? value})>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.colors;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xxl,
                Space.sm,
                Space.xxl,
                Space.md,
              ),
              child: Text(
                title,
                style: AppType.sectionTitle.copyWith(color: c.text),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.xxl),
                child: Text(
                  emptyMessage ?? 'Nothing to choose from.',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.xxl),
                  children: [
                    if (clearLabel != null)
                      _OptionTile(
                        title: clearLabel,
                        selected: selected == null,
                        onTap: () => Navigator.of(ctx).pop((value: null)),
                      ),
                    for (final o in options)
                      _OptionTile(
                        title: o.title,
                        subtitle: o.subtitle,
                        selected: o.value == selected,
                        onTap: () => Navigator.of(ctx).pop((value: o.value)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touchTarget + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xxl,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppType.bodySmall.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: c.primaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
