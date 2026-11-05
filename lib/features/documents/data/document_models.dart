import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Document types the backend uses.
abstract final class DocType {
  static const photo = 'PHOTO';
  static const plan = 'PLAN';
  static const contract = 'CONTRACT';
  static const receipt = 'RECEIPT';
  static const permit = 'PERMIT';
  static const certificate = 'CERTIFICATE';
  static const other = 'OTHER';

  /// In the order a site person would pick them.
  static const all = [
    photo,
    plan,
    permit,
    certificate,
    receipt,
    contract,
    other,
  ];

  static String label(String type) => switch (type) {
    'PHOTO' => 'Photo',
    'PLAN' => 'Plan or drawing',
    'CONTRACT' => 'Contract',
    'RECEIPT' => 'Receipt',
    'PERMIT' => 'Permit',
    'CERTIFICATE' => 'Certificate',
    _ => 'Other',
  };
}

/// Document approval statuses the backend uses.
abstract final class DocApproval {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const expired = 'EXPIRED';
}

/// A file attached to a project.
///
/// The server keeps the web address of the file in the `folder` column (a
/// quirk of how project documents are stored), and the address is only as good
/// as the server's file storage (backend-gaps G5), so it may not open.
@immutable
class ProjectDocument {
  const ProjectDocument({
    required this.id,
    required this.name,
    required this.type,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
    required this.approval,
    this.url,
    this.uploaderId,
    this.isRequired = false,
    this.version = 1,
  });

  final String id;
  final String name;
  final String type;
  final String contentType;
  final int sizeBytes;
  final DateTime createdAt;
  final String approval;

  /// Where the file can be fetched, when the server recorded a web address.
  final String? url;
  final String? uploaderId;
  final bool isRequired;
  final int version;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';
  bool get isSpreadsheet =>
      contentType == 'application/vnd.ms-excel' ||
      contentType.contains('spreadsheetml');
  bool get needsApproval => approval == DocApproval.pending;

  static ProjectDocument? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['fileName']);
    if (id == null || name == null) return null;
    final folder = J.str(m['folder']);
    final isLink =
        folder != null &&
        (folder.startsWith('http://') || folder.startsWith('https://'));
    return ProjectDocument(
      id: id,
      name: name,
      type: J.strOr(m['type'], DocType.other),
      contentType: J.strOr(m['contentType']),
      sizeBytes: J.integer(m['sizeBytes']) ?? 0,
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      approval: J.strOr(m['approvalStatus'], DocApproval.pending),
      url: isLink ? folder : null,
      uploaderId: J.str(m['uploaderId']),
      isRequired: J.boolean(m['isRequired']),
      version: J.integer(m['version']) ?? 1,
    );
  }
}

/// Photos the phone can produce from the camera or gallery.
const documentImageMimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// PDF, Word and Excel files, picked from the phone's files.
const documentFileMimeTypes = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/// The file extensions the picker offers (the server's allowed list minus the
/// photos, which have their own camera and gallery options).
final documentFileExtensions = documentFileMimeTypes.keys.toList();

/// The server refuses documents above 20 MB.
const maxDocumentBytes = 20 * 1024 * 1024;

/// The mime type the server accepts for this file name, or null when it takes
/// none (a HEIC photo, a ZIP…).
String? documentMimeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return documentImageMimeTypes[ext] ?? documentFileMimeTypes[ext];
}
