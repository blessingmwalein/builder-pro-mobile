import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../../shared/services/document_picker.dart';
import '../../../shared/services/photo_picker.dart';
import '../application/documents_providers.dart';
import '../data/document_models.dart';

/// A project's documents: see what is on file, open one, and (with `projects.*`)
/// add a photo from the camera or gallery, or a PDF, Word or Excel file from the
/// phone's files (up to 20 MB). Opening uses the web address
/// the server stored, so it works only as far as the server's file storage does
/// (backend-gaps G5).
class ProjectDocumentsSection extends ConsumerStatefulWidget {
  const ProjectDocumentsSection({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectDocumentsSection> createState() =>
      _ProjectDocumentsSectionState();
}

enum _DocSource { camera, gallery, file }

/// What the person chose to add, from the camera, gallery or the phone's files.
/// The size is null when the source does not say (photos).
class _Chosen {
  const _Chosen(this.path, this.name, this.sizeBytes);
  final String path;
  final String name;
  final int? sizeBytes;
}

class _ProjectDocumentsSectionState
    extends ConsumerState<ProjectDocumentsSection> {
  double? _progress;

  Future<_Chosen?> _pickPhoto(PhotoSource source) async {
    final photo = await ref.read(photoPickerProvider).pick(source);
    return photo == null ? null : _Chosen(photo.path, photo.name, null);
  }

  Future<_Chosen?> _pickFile() async {
    final doc = await ref
        .read(documentPickerProvider)
        .pick(extensions: documentFileExtensions);
    return doc == null ? null : _Chosen(doc.path, doc.name, doc.sizeBytes);
  }

  Future<void> _open(ProjectDocument d) async {
    final url = d.url;
    if (url == null) {
      Snack.show(
        context,
        'The server has no link for this document. Ask your administrator to check file storage.',
      );
      return;
    }
    final ok = await ref.read(contactLauncherProvider).openLink(url);
    if (!ok && mounted) {
      Snack.show(context, 'Could not open the document. Try again later.');
    }
  }

  Future<void> _add() async {
    if (_progress != null) return;
    final source = await pickOne<_DocSource>(
      context,
      title: 'Add a document',
      options: const [
        PickerOption(value: _DocSource.camera, title: 'Take a photo'),
        PickerOption(
          value: _DocSource.gallery,
          title: 'Choose a photo from the gallery',
        ),
        PickerOption(
          value: _DocSource.file,
          title: 'Choose a PDF, Word or Excel file',
        ),
      ],
    );
    final chosen = source?.value;
    if (chosen == null || !mounted) return;

    final _Chosen? picked;
    try {
      picked = chosen == _DocSource.file
          ? await _pickFile()
          : await _pickPhoto(
              chosen == _DocSource.camera
                  ? PhotoSource.camera
                  : PhotoSource.gallery,
            );
    } catch (_) {
      if (mounted) {
        Snack.show(context, switch (chosen) {
          _DocSource.camera =>
            'Could not open the camera. Check the app has permission.',
          _DocSource.gallery =>
            'Could not open the gallery. Check the app has permission.',
          _DocSource.file => 'Could not open that file. Choose one stored on this phone, or download it first.',
        });
      }
      return;
    }
    if (picked == null || !mounted) return;

    final mime = documentMimeFor(picked.name);
    if (mime == null) {
      Snack.show(
        context,
        'That file type is not supported. Use a JPG, PNG or WebP photo, or a PDF, Word or Excel file.',
      );
      return;
    }
    final size = picked.sizeBytes;
    if (size != null && size > maxDocumentBytes) {
      Snack.show(
        context,
        'That file is ${Fmt.bytes(size)}. The limit is ${Fmt.bytes(maxDocumentBytes)}.',
      );
      return;
    }
    if (size != null && size == 0) {
      Snack.show(context, 'That file is empty.');
      return;
    }

    final type = await pickOne<String>(
      context,
      title: 'What is it?',
      options: [
        for (final t in DocType.all)
          PickerOption(value: t, title: DocType.label(t)),
      ],
    );
    final chosenType = type?.value;
    if (chosenType == null || !mounted) return;

    setState(() => _progress = 0);
    try {
      final note = await ref
          .read(documentActionsProvider)
          .upload(
            projectId: widget.projectId,
            path: picked.path,
            fileName: picked.name,
            contentType: mime,
            type: chosenType,
            onProgress: (sent, total) {
              if (mounted && total > 0) {
                setState(() => _progress = sent / total);
              }
            },
          );
      if (mounted) Snack.show(context, note ?? 'Document added.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canUpload = ref
        .watch(permissionsProvider)
        .hasAny(Feature.documentsUpload);
    final docs = ref.watch(projectDocumentsProvider(widget.projectId));
    return docs.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.xl),
        child: SkeletonList(rows: 1, rowHeight: 80),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () =>
              ref.invalidate(projectDocumentsProvider(widget.projectId)),
        ),
      ),
      data: (list) {
        if (list.isEmpty && !canUpload) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('DOCUMENTS ${list.length}'),
            if (list.isEmpty)
              AppCard(
                child: Text(
                  'No documents on file yet.',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
              ),
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _DocumentCard(document: d, onTap: () => _open(d)),
              ),
            if (canUpload) ...[
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'Add a document',
                icon: Icons.upload_file_outlined,
                variant: AppButtonVariant.secondary,
                loading: _progress != null,
                onPressed: _progress != null ? null : _add,
              ),
              if (_progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onTap});
  final ProjectDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = document;
    final facts = [
      DocType.label(d.type),
      if (d.sizeBytes > 0) Fmt.bytes(d.sizeBytes),
      Fmt.day(d.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return AppCard(
      onTap: onTap,
      semanticLabel: '${d.name}, $facts, tap to open',
      child: Row(
        children: [
          IconTile(
            d.isImage
                ? Icons.image_outlined
                : d.isPdf
                ? Icons.picture_as_pdf_outlined
                : d.isSpreadsheet
                ? Icons.table_chart_outlined
                : Icons.description_outlined,
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                Text(facts, style: AppType.helper.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          if (d.approval != DocApproval.approved) ...[
            const SizedBox(width: Space.sm),
            StatusBadge.status(d.approval, dense: true),
          ],
        ],
      ),
    );
  }
}
