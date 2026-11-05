import 'package:flutter/material.dart';

/// The ownit2buildit logo from the web app. On dark surfaces it is rendered
/// white (the web uses `brightness-0 invert` for the same effect).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.height = 56, this.forceLight = false});

  final double height;

  /// Render white regardless of theme (for use on the dark brand panel).
  final bool forceLight;

  @override
  Widget build(BuildContext context) {
    final dark = forceLight || Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'ownit2buildit',
    );
    if (!dark) return image;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: image,
    );
  }
}
