import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

class PickedPhoto {
  const PickedPhoto({required this.path, required this.name});
  final String path;
  final String name;
}

/// Camera / gallery access behind a small interface so screens can be tested
/// without the platform plugin.
abstract class PhotoPicker {
  /// Null when the user cancelled.
  Future<PickedPhoto?> pick(PhotoSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    // Downscaling keeps site photos well under the 20 MB limit and, on iOS,
    // re-encodes HEIC as JPEG (the server does not accept HEIC).
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 82,
    );
    return file == null ? null : PickedPhoto(path: file.path, name: file.name);
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => ImagePickerPhotoPicker(),
);
