import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../projects/application/projects_providers.dart';
import '../../projects/data/project_models.dart';
import '../../projects/presentation/project_picker.dart';
import '../../team/application/team_providers.dart';
import '../../team/data/team_models.dart';
import '../application/messaging_providers.dart';
import 'chat_widgets.dart';

enum _Kind { direct, group }

/// Starts a chat the way the web app does: a direct message to one person, or a
/// group linked to a project with its own name and people. Needs
/// `messaging.send`. Choosing from the whole company needs permission to see the
/// team; without it the group can still be made from the project's own team.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  Timer? _debounce;
  _Kind _kind = _Kind.direct;
  ProjectSummary? _project;
  final _chosen = <String, String>{};
  var _people = <TeamMember>[];
  var _page = 0;
  var _hasMore = false;
  var _loading = false;
  var _loadingMore = false;
  var _busy = false;
  AppException? _error;

  /// A newer search wins over a slower older one.
  var _generation = 0;

  bool get _hasDirectory => ref.read(permissionsProvider).hasAny(Feature.team);

  @override
  void initState() {
    super.initState();
    if (_hasDirectory) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(''));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _title.dispose();
    super.dispose();
  }

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
        _people = result.items;
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
      final known = _people.map((p) => p.id).toSet();
      setState(() {
        _people = [
          ..._people,
          ...result.items.where((p) => !known.contains(p.id)),
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

  Future<void> _openDirect(TeamMember person) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(chatActionsProvider).openDirect(person.id);
      if (!mounted) return;
      context.pushReplacement('/messages/$id');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickProject() async {
    final picked = await chooseProject(
      context,
      ref,
      title: 'Which project is the group for?',
      selected: _project,
    );
    if (picked?.value == null || !mounted) return;
    setState(() => _project = picked!.value);
  }

  /// Adds everyone on the project's team to the group.
  Future<void> _addProjectTeam() async {
    final p = _project;
    if (p == null) return;
    try {
      final detail = await ref.read(projectDetailProvider(p.id).future);
      final me = ref.read(currentUserIdProvider);
      if (!mounted) return;
      setState(() {
        for (final m in detail.members) {
          if (m.id != me) _chosen[m.id] = m.name;
        }
      });
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    }
  }

  Future<void> _createGroup() async {
    if (_busy) return;
    if (_project == null) {
      Snack.show(context, 'Choose the project the group is for.');
      return;
    }
    if (_chosen.isEmpty) {
      Snack.show(context, 'Add at least one person to the group.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(chatActionsProvider)
          .createGroup(
            projectId: _project!.id,
            participantIds: _chosen.keys.toList(),
            title: _title.text,
          );
      if (!mounted) return;
      context.pushReplacement('/messages/$id');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: SafeArea(
        child: !perms.hasAny(Feature.messagingSend)
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot start chats.',
              )
            : PageBody(
                children: [
                  SegmentedButton<_Kind>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _Kind.direct,
                        icon: Icon(Icons.person_outline_rounded),
                        label: Text('Direct message'),
                      ),
                      ButtonSegment(
                        value: _Kind.group,
                        icon: Icon(Icons.groups_outlined),
                        label: Text('Group'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: Space.lg),
                  if (_kind == _Kind.group) ...[
                    PickerField(
                      label: 'Project',
                      icon: Icons.apartment_rounded,
                      value: _project?.label,
                      placeholder: 'Choose the project',
                      enabled: !_busy,
                      onTap: _pickProject,
                    ),
                    const SizedBox(height: Space.lg),
                    AppTextField(
                      label: 'Group name (optional)',
                      controller: _title,
                      enabled: !_busy,
                      hint: 'e.g. Site team',
                      textCapitalization: TextCapitalization.words,
                    ),
                    if (_project != null && perms.hasAny(Feature.projects))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy ? null : _addProjectTeam,
                          icon: const Icon(Icons.group_add_outlined, size: 18),
                          label: const Text('Add the project team'),
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    if (_chosen.isNotEmpty) ...[
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        children: [
                          for (final e in _chosen.entries)
                            InputChip(
                              label: Text(e.value),
                              onDeleted: _busy
                                  ? null
                                  : () => setState(() => _chosen.remove(e.key)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                    ],
                  ],
                  if (_hasDirectory) ...[
                    AppTextField(
                      label: _kind == _Kind.direct
                          ? 'Who do you want to message?'
                          : 'Add people',
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
                    const SizedBox(height: Space.md),
                    _peopleList(c, me),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text(
                        _kind == _Kind.direct
                            ? 'Your role cannot browse the company\'s people. To message someone, open their card in a project\'s team.'
                            : 'Your role cannot browse the company\'s people, so choose a project and add its team.',
                        style: AppType.bodySmall.copyWith(color: c.textMuted),
                      ),
                    ),
                  if (_kind == _Kind.group) ...[
                    const SizedBox(height: Space.xxl),
                    AppButton(
                      label: 'Create group',
                      icon: Icons.check_rounded,
                      loading: _busy,
                      onPressed: _createGroup,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _peopleList(AppColors c, String? me) {
    if (_loading) return const SkeletonList(rows: 4, rowHeight: 56);
    if (_error != null && _people.isEmpty) {
      return ErrorPanel(
        error: _error!,
        compact: true,
        onRetry: () => _load(_search.text),
      );
    }
    final people = _people.where((p) => p.id != me).toList();
    if (people.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No one found',
        message: 'Try a different name or email.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: InkWell(
              borderRadius: BorderRadius.circular(Corners.md),
              onTap: _busy
                  ? null
                  : () {
                      if (_kind == _Kind.direct) {
                        _openDirect(p);
                      } else {
                        setState(() {
                          if (_chosen.containsKey(p.id)) {
                            _chosen.remove(p.id);
                          } else {
                            _chosen[p.id] = p.name;
                          }
                        });
                      }
                    },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs,
                    vertical: Space.xs,
                  ),
                  child: Row(
                    children: [
                      ChatAvatar(name: p.name, size: 44),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.bodyStrong.copyWith(color: c.text),
                            ),
                            if (p.roleLabel.isNotEmpty)
                              Text(
                                p.roleLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.helper.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_kind == _Kind.group)
                        Icon(
                          _chosen.containsKey(p.id)
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: _chosen.containsKey(p.id)
                              ? c.primary
                              : c.textMuted,
                        )
                      else
                        Icon(Icons.chevron_right_rounded, color: c.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: AppButton(
              label: 'Show more',
              variant: AppButtonVariant.secondary,
              loading: _loadingMore,
              onPressed: _more,
            ),
          ),
      ],
    );
  }
}
