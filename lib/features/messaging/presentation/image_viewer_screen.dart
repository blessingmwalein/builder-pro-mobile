import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_typography.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/services/contact_launcher.dart';

/// A photo to show full screen: from the server (a [url]) or still on the phone
/// (a [path]).
class ViewerImage {
  const ViewerImage({this.url, this.path, required this.title});
  final String? url;
  final String? path;
  final String title;
}

class ImageViewerArgs {
  const ImageViewerArgs({required this.images, required this.index});
  final List<ViewerImage> images;
  final int index;
}

/// The photos of a message full screen: swipe between them, pinch to zoom, and
/// open the current one outside the app.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.args});
  final ImageViewerArgs args;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late final _pages = PageController(initialPage: widget.args.index);
  late int _current = widget.args.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _openOutside() async {
    final url = widget.args.images[_current].url;
    if (url == null) return;
    final ok = await ref.read(contactLauncherProvider).openLink(url);
    if (!ok && mounted) {
      Snack.show(context, 'Could not open the photo. Try again later.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.args.images;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          images.isEmpty ? 'Photo' : images[_current].title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.bodyStrong.copyWith(color: Colors.white),
        ),
        actions: [
          if (images.isNotEmpty && images[_current].url != null)
            IconButton(
              tooltip: 'Open outside the app',
              onPressed: _openOutside,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: images.isEmpty
          ? const SizedBox.shrink()
          : Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) {
                    final img = images[i];
                    final Widget picture = img.path != null
                        ? Image.file(File(img.path!), fit: BoxFit.contain)
                        : Image.network(
                            img.url ?? '',
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 48,
                              ),
                            ),
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                          );
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(child: picture),
                    );
                  },
                ),
                if (images.length > 1)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${_current + 1} of ${images.length}',
                          style: AppType.helper.copyWith(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
