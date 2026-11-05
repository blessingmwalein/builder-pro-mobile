import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PickedDocument {
  const PickedDocument({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });
  final String path;
  final String name;
  final int sizeBytes;
}

/// The phone's file chooser behind a small interface so screens can be tested
/// without the platform plugin.
abstract class DocumentPicker {
  /// One file of the given types, or null when the user cancelled. Throws when
  /// the chosen file cannot be read from local storage (some cloud files).
  Future<PickedDocument?> pick({required List<String> extensions});
}

class FilePickerDocumentPicker implements DocumentPicker {
  @override
  Future<PickedDocument?> pick({required List<String> extensions}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    final path = file.path;
    if (path == null) {
      throw const FormatException('The chosen file has no local path.');
    }
    final size = file.lengthSync() ?? await file.length() ?? 0;
    return PickedDocument(path: path, name: file.name, sizeBytes: size);
  }
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => FilePickerDocumentPicker(),
);
