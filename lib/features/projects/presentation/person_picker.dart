import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/states.dart';
import '../../team/application/team_providers.dart';
import '../../team/data/team_models.dart';
import '../data/project_models.dart';

/// Someone chosen from a list of people.
class PersonChoice {
  const PersonChoice({required this.id, required this.name, this.detail});
  final String id;
  final String name;

  /// Their roles or their role on the project.
  final String? detail;
}

/// Lets the person choose someone. With the company directory ([directory], which
/// needs permission to see the team) they search everyone; without it the only
/// choices are the people already on [members]. Returns null when dismissed.
Future<PersonChoice?> choosePerson(
  BuildContext context, {
  required String title,
  required bool directory,
  List<PersonRef> members = const [],
  String? selectedId,
}) {
  return showModalBottomSheet<PersonChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _PersonSheet(
      title: title,
      directory: directory,
      members: members,
      selectedId: selectedId,
    ),
  );
}

class _PersonSheet extends ConsumerStatefulWidget {
  const _PersonSheet({
    required this.title,
    required this.directory,
    required this.members,
    required this.selectedId,
  });
  final String title;
  final bool directory;
  final List<PersonRef> members;
  final String? selectedId;

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _items = <PersonChoice>[];
  var _page = 0;
  var _hasMore = false;
  var _loading = true;
  var _loadingMore = false;
  AppException? _error;

  /// A newer search wins over a slower older one.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.directory) {
      _load('');
    } else {
      _items = [
        for (final m in widget.members)
          PersonChoice(id: m.id, name: m.name, detail: m.role),
      ];
      _loading = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  static PersonChoice _choice(TeamMember m) =>
      PersonChoice(id: m.id, name: m.name, detail: m.roleLabel);

  Future<void> _load(String query) async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(teamRepositoryProvider)
          .list(search: query.trim().isEmpty ? null : query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = result.items.map(_choice).toList();
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final result = await ref
          .read(teamRepositoryProvider)
          .list(
            search: _search.text.trim().isEmpty ? null : _search.text,
            page: _page + 1,
          );
      if (!mounted || gen != _generation) return;
      final known = _items.map((p) => p.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...result.items.map(_choice).where((p) => !known.contains(p.id)),
        ];
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } on AppException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
                widget.title,
                style: AppType.sectionTitle.copyWith(color: c.text),
              ),
            ),
            if (widget.directory) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                child: AppTextField(
                  label: 'Search people',
                  controller: _search,
                  hint: 'Name or email',
                  prefixIcon: Icons.search_rounded,
                  onChanged: (t) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(t),
                    );
                  },
                ),
              ),
              const SizedBox(height: Space.md),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xxl,
                  0,
                  Space.xxl,
                  Space.md,
                ),
                child: Text(
                  'Only people already on this project can be chosen here. Seeing everyone needs permission to view the team.',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ),
            Flexible(child: _body(c)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppColors c) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: SkeletonList(rows: 3, rowHeight: 56),
      );
    }
    if (_error != null && _items.isEmpty) {
      return ErrorPanel(
        error: _error!,
        compact: true,
        onRetry: () => _load(_search.text),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: EmptyState(
          icon: Icons.groups_2_outlined,
          title: 'No one to choose',
          message: 'Try a different name, or add people to the project team.',
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final p in _items)
          InkWell(
            onTap: () => Navigator.of(context).pop(p),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: Sizes.touchTarget + 4,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.xxl,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: AppType.bodyStrong.copyWith(color: c.text),
                          ),
                          if (p.detail != null && p.detail!.isNotEmpty)
                            Text(
                              p.detail!,
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (p.id == widget.selectedId)
                      Icon(Icons.check_rounded, color: c.primary),
                  ],
                ),
              ),
            ),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: AppButton(
              label: 'Show more',
              variant: AppButtonVariant.secondary,
              loading: _loadingMore,
              onPressed: _more,
            ),
          ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}
